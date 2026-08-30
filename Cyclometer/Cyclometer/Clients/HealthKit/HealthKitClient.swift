import ComposableArchitecture
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
    var heartRateStream:       @Sendable () -> AsyncStream<Int>     // live BPM from Watch / HR strap
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
            heartRateStream:       { makeHeartRateStream(store) }
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
        heartRateStream:       { AsyncStream { $0.finish() } }
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

extension DependencyValues {
    var healthKitClient: HealthKitClient {
        get { self[HealthKitClient.self] }
        set { self[HealthKitClient.self] = newValue }
    }
}
