import ComposableArchitecture
import CoreLocation
import HealthKit
import os

// Stream live: Console.app / Xcode console, filter subsystem "com.xavier.cyclometer".
private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "healthkit")

private let bpmUnit = HKUnit.count().unitDivided(by: .minute())

/// A resting-HR sample older than this is not "current" — a rider who last wore a
/// Watch months ago should fall through to a manual override or the default, not have
/// a stale reading silently drive the Karvonen calculation.
private let restingHeartRateStalenessWindow: TimeInterval = 30 * 24 * 60 * 60

/// How long to wait before re-establishing the live heart-rate query after it's
/// interrupted. A rider mid-ride should not lose the HR tile to one transient
/// HealthKit hiccup.
private let heartRateStreamRetryDelay: Duration = .seconds(5)

private enum WorkoutWriteError: LocalizedError {
    case endsBeforeStart
    var errorDescription: String? { "the ride ends before it starts (device clock changed mid-ride?)" }
}

/// The app's single `HKHealthStore`, shared with `PermissionProbes` so authorization
/// and data reads talk to the same handle rather than two.
enum HealthKitStore {
    static let shared = HKHealthStore()
}

/// TCA dependency for HealthKit.
///
/// Resting heart rate feeds the Karvonen zone computation as the middle term of
/// `RiderProfile`'s `override ?? healthKit ?? default` resolution (DataModel.md §3.5).
/// A manual override in S12 wins over it; the app stores nothing otherwise.
///
/// **There is deliberately no `fetchMaxHeartRate`.** HealthKit has no max-heart-rate
/// type — only `heartRate`, `restingHeartRate`, `walkingHeartRateAverage`,
/// `heartRateVariabilitySDNN` and `heartRateRecoveryOneMinute`. A `.discreteMax` query
/// over historical `heartRate` samples returns *highest ever observed*, which
/// understates any rider who has not gone near their limit wearing a watch, so it is
/// not used. Max HR comes from the 220 − age estimate built on the `dateOfBirth`
/// characteristic, or from manual entry (PRD §8.5, §9.4). A stub promising otherwise
/// stood here until #96 and misled the plan for that issue.
struct HealthKitClient {
    var requestAuthorization:  @Sendable () async throws -> Void
    var fetchRestingHeartRate: @Sendable () async throws -> Int?
    /// For the 220 − age max estimate. `nil` when the rider has not set one.
    var fetchDateOfBirth:      @Sendable () async throws -> DateComponents?
    /// The rider's latest weight in kilograms, for the ride's energy estimate (#276). `nil`
    /// when Health has none or read access is denied, and then no energy is written.
    var fetchBodyMass:         @Sendable () async throws -> Double?
    var heartRateStream:       @Sendable () -> AsyncStream<Int>     // live BPM from Watch / HR strap
    /// UX.md §S10 — the finished ride as an outdoor cycling `HKWorkout`. Skipped, not
    /// thrown, when another source already recorded a cycling workout over the same
    /// time; logs its own failures before rethrowing them.
    var saveWorkout:           @Sendable (RideWorkout) async throws -> Void
}

extension HealthKitClient: DependencyKey {
    /// One guard for the whole client rather than one per function: availability is a
    /// device capability fixed for the process lifetime, not a live authorization
    /// state, so checking it once here and falling back to `testValue`'s no-op shape
    /// covers every closure without repeating the check four times.
    static let liveValue: HealthKitClient = {
        guard HKHealthStore.isHealthDataAvailable() else { return .testValue }
        let store = HealthKitStore.shared
        return HealthKitClient(
            requestAuthorization:  { try await requestAuthorization(store) },
            fetchRestingHeartRate: { try await fetchRestingHeartRate(store) },
            fetchDateOfBirth:      { fetchDateOfBirth(store) },
            fetchBodyMass:         { try await fetchBodyMass(store) },
            heartRateStream:       { makeHeartRateStream(store) },
            saveWorkout:           { try await saveWorkout($0, store) }
        )
    }()

    /// `nil` rather than a plausible-looking number: an unread value has no value, and
    /// `RiderProfile` resolution already treats absence as "fall through to the
    /// default". Returning 55 here — as this stub did before #96 — would have silently
    /// beaten the corrected 60 default the moment M5 wired it up.
    static let testValue = HealthKitClient(
        requestAuthorization:  { },
        fetchRestingHeartRate: { nil },
        fetchDateOfBirth:      { nil },
        fetchBodyMass:         { nil },
        heartRateStream:       { AsyncStream { $0.finish() } },
        saveWorkout:           { _ in }
    )
}

// MARK: - Live implementation

extension HealthKitClient {

    /// Skips the request entirely once already resolved. `PermissionsClient`'s S01
    /// flow (`PermissionProbes.requestHealth`) is the app's primary authorization
    /// surface and will have already asked in virtually every case by the time a ride
    /// starts — without this check, a call here would race that one on the same
    /// `HKHealthStore` for no benefit.
    private static func requestAuthorization(_ store: HKHealthStore) async throws {
        let requestStatus = try await store.statusForAuthorizationRequest(
            toShare: PermissionsClient.healthShareTypes,
            read: PermissionsClient.healthReadTypes
        )
        guard requestStatus != .unnecessary else { return }
        try await store.requestAuthorization(
            toShare: PermissionsClient.healthShareTypes,
            read: PermissionsClient.healthReadTypes
        )
    }

    /// Bounded to the last `restingHeartRateStalenessWindow` — an old sample is
    /// dropped rather than surfaced as if it were today's reading.
    private static func fetchRestingHeartRate(_ store: HKHealthStore) async throws -> Int? {
        let recent = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-restingHeartRateStalenessWindow),
            end: nil,
            options: .strictStartDate
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: PermissionsClient.restingHeartRateType, predicate: recent)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        let samples = try await descriptor.result(for: store)
        guard let sample = samples.first else { return nil }
        return Int(sample.quantity.doubleValue(for: bpmUnit).rounded())
    }

    /// The latest sample however old: unlike resting heart rate, weight drifts slowly, and a
    /// months-old reading still estimates energy better than none. A denied read returns no
    /// samples rather than throwing, so it lands on `nil` like an empty history.
    private static func fetchBodyMass(_ store: HKHealthStore) async throws -> Double? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: PermissionsClient.bodyMassType)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        let samples = try await descriptor.result(for: store)
        return samples.first?.quantity.doubleValue(for: .gramUnit(with: .kilo))
    }

    /// `dateOfBirthComponents()` throws both when the rider has never set a birthdate
    /// in Health and when access hasn't been granted — HealthKit gives no way to tell
    /// those apart, so both collapse to `nil` here the same way an empty query result
    /// does for the quantity reads above.
    private static func fetchDateOfBirth(_ store: HKHealthStore) -> DateComponents? {
        try? store.dateOfBirthComponents()
    }

    /// A live-only feed: the predicate bounds every query to samples starting at or
    /// after the moment it runs, so neither the first connection nor a reconnect after
    /// an error ever replays a rider's historical archive as if it just happened. On
    /// any error the query is re-established after `heartRateStreamRetryDelay` rather
    /// than ending the stream for good.
    ///
    /// **Not a 1Hz feed.** This only yields whatever HR samples the Watch has already
    /// written to HealthKit, and the Watch does not write at 1Hz — outside an active
    /// workout session those writes land minutes apart, and even during one they come
    /// in multi-second batches. `ActiveRideFeature`'s fallback tile updates in sparse,
    /// irregular bursts on this source, by design — a true live per-second HR feed
    /// needs a Watch companion app streaming directly (`HKLiveWorkoutBuilder`/
    /// `HKWorkoutSession` on-device, pushed over Watch Connectivity), which is PRD
    /// §S17's Apple Watch companion, currently Phase 2/deferred.
    private static func makeHeartRateStream(_ store: HKHealthStore) -> AsyncStream<Int> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    let liveOnly = HKQuery.predicateForSamples(withStart: Date(), end: nil, options: .strictStartDate)
                    let descriptor = HKAnchoredObjectQueryDescriptor(
                        predicates: [.quantitySample(type: PermissionsClient.heartRateType, predicate: liveOnly)],
                        anchor: nil,
                        limit: nil
                    )
                    do {
                        for try await update in descriptor.results(for: store) {
                            for sample in update.addedSamples {
                                continuation.yield(Int(sample.quantity.doubleValue(for: bpmUnit).rounded()))
                            }
                        }
                    } catch {
                        logger.error(
                            "heart rate stream interrupted, retrying: \(error.localizedDescription, privacy: .public)"
                        )
                        try? await Task.sleep(for: heartRateStreamRetryDelay)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension HealthKitClient {

    /// Overlap is the whole duplicate test: a Watch recording an Outdoor Cycle alongside the
    /// phone writes its own workout over the same stretch of time (#250). Only another
    /// source's counts — ours carry a sync identifier, so a rewrite replaces rather than
    /// duplicates. A denied workout read can't be told apart from "none found", so it falls
    /// through to writing.
    ///
    /// Written after the ride is saved and never awaited by the summary (UX.md §S10), so a
    /// failure here can only cost the workout, which is logged rather than surfaced — §S10
    /// leaves notifying the rider open.
    private static func saveWorkout(_ workout: RideWorkout, _ store: HKHealthStore) async throws {
        var builder: HKWorkoutBuilder?
        do {
            // `HKQuantitySample` raises an Objective-C exception, which Swift can't catch, on an
            // end before its start. A clock set back mid-ride can produce one.
            guard workout.endedAt > workout.startedAt else { throw WorkoutWriteError.endsBeforeStart }

            if let existing = await overlappingCyclingWorkout(workout, store) {
                logger.notice(
                    "workout for ride \(workout.rideId, privacy: .public) skipped — \(existing.sourceRevision.source.name, privacy: .public) already recorded one over the same time"
                )
                return
            }

            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .cycling
            configuration.locationType = .outdoor
            let started = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
            builder = started

            try await started.beginCollection(at: workout.startedAt)
            // A ride that never moved has no distance to record. Share access is per type on
            // HealthKit's sheet: a rider can allow Workouts and leave Cycling Distance off, and
            // then the sample would fail the whole workout rather than just go missing.
            if workout.distanceMeters > 0,
               store.authorizationStatus(for: PermissionsClient.distanceCyclingType) == .sharingAuthorized {
                try await started.addSamples([HKQuantitySample(
                    type: PermissionsClient.distanceCyclingType,
                    quantity: HKQuantity(unit: .meter(), doubleValue: workout.distanceMeters),
                    start: workout.startedAt,
                    end: workout.endedAt,
                    // Its own sync identifier: the workout's replaces only the workout, and a
                    // rewrite would otherwise leave a second sample doubling the ride's distance.
                    metadata: syncMetadata("\(workout.rideId.uuidString)-distance")
                )])
            }
            // Nil without body mass (#276). Per-type share access, as for distance.
            if let kilocalories = workout.activeEnergyKilocalories, kilocalories > 0,
               store.authorizationStatus(for: PermissionsClient.activeEnergyBurnedType) == .sharingAuthorized {
                try await started.addSamples([HKQuantitySample(
                    type: PermissionsClient.activeEnergyBurnedType,
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kilocalories),
                    start: workout.startedAt,
                    end: workout.endedAt,
                    metadata: syncMetadata("\(workout.rideId.uuidString)-energy")
                )])
            }
            try await started.addMetadata(syncMetadata(workout.rideId.uuidString))
            try await started.endCollection(at: workout.endedAt)
            if let saved = try await started.finishWorkout() {
                await saveRoute(workout, to: saved, store)
            }
        } catch {
            // Nothing half-written is left behind: any sample the builder already took goes too.
            builder?.discardWorkout()
            logger.error(
                "workout write failed for ride \(workout.rideId, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }

    /// The map Fitness draws for the ride (#295). Attached to the workout once it is saved,
    /// and never allowed to cost it: share access is per type, so a rider can allow Workouts
    /// and leave Workout Routes off, and a route that fails is logged and dropped rather than
    /// taking the workout down with it.
    private static func saveRoute(_ workout: RideWorkout, to saved: HKWorkout, _ store: HKHealthStore) async {
        guard !workout.trackPoints.isEmpty,
              store.authorizationStatus(for: PermissionsClient.workoutRouteType) == .sharingAuthorized
        else { return }
        let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: .local())
        do {
            try await routeBuilder.insertRouteData(routeLocations(workout.trackPoints))
            // Its own sync identifier, like the distance sample's.
            try await routeBuilder.finishRoute(with: saved, metadata: syncMetadata("\(workout.rideId.uuidString)-route"))
        } catch {
            routeBuilder.discard()
            logger.error(
                "workout route write failed for ride \(workout.rideId, privacy: .public), workout kept without a map: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Only what a track point records: course and vertical accuracy never were, so both go
    /// in as CoreLocation's "invalid" −1 — which also marks the altitude unusable — and a
    /// second with no speed reading gets the same.
    static func routeLocations(_ points: [TrackPointDTO]) -> [CLLocation] {
        points.map { point in
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude),
                altitude: point.altitudeMeters,
                horizontalAccuracy: point.horizontalAccuracyMeters,
                verticalAccuracy: -1,
                course: -1,
                speed: point.speedMPS ?? -1,
                timestamp: point.timestamp
            )
        }
    }

    private static func syncMetadata(_ identifier: String) -> [String: Any] {
        [HKMetadataKeySyncIdentifier: identifier, HKMetadataKeySyncVersion: 1]
    }

    /// Best effort, like a denied read: a query that fails (a locked device's store, say)
    /// counts as "none found" rather than costing the workout.
    private static func overlappingCyclingWorkout(_ workout: RideWorkout, _ store: HKHealthStore) async -> HKWorkout? {
        do {
            return try await queryOverlappingCyclingWorkout(workout, store)
        } catch {
            logger.notice(
                "overlap check failed for ride \(workout.rideId, privacy: .public), writing anyway: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    private static func queryOverlappingCyclingWorkout(_ workout: RideWorkout, _ store: HKHealthStore) async throws -> HKWorkout? {
        let fromOtherSources = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .cycling),
            // No options: any workout that overlaps the ride at all, not only one inside it.
            HKQuery.predicateForSamples(withStart: workout.startedAt, end: workout.endedAt),
            NSCompoundPredicate(notPredicateWithSubpredicate: HKQuery.predicateForObjects(from: .default())),
        ])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(fromOtherSources)],
            sortDescriptors: [],
            limit: 1
        )
        return try await descriptor.result(for: store).first
    }
}

extension DependencyValues {
    var healthKitClient: HealthKitClient {
        get { self[HealthKitClient.self] }
        set { self[HealthKitClient.self] = newValue }
    }
}
