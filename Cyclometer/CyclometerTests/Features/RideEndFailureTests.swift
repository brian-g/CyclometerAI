import ComposableArchitecture
import Foundation
import SwiftData
import Testing
import UIKit
@testable import Cyclometer

/// #188: the ride-end sequence (`ActiveRideFeature.finishAlert(.presented(.confirmFinish))`)
/// has three writes that can fail, and every one of them was swallowed and untested.
/// Two degrade acceptably — a truncated export, a nil `gpxFileURL` — and this suite pins
/// that they still end the ride. The third did not: `finalizeRide` is the only thing that
/// sets `Ride.endedAt`, and `fetchResumableRide` treats a nil `endedAt` as "still in
/// progress", so a failed finalize made a finished ride come back as resumable at the next
/// launch.
///
/// Built on the real persistence stack with exactly one endpoint swapped for a throwing
/// one, so each test exercises the genuine pipeline around the single failure it induces.
@MainActor
@Suite("Ride end — failure paths")
struct RideEndFailureTests {
    private struct WriteFailed: Error {}

    private static let testDate = Date(timeIntervalSince1970: 1_000_000)
    private static let coordinate = Coordinate(latitude: 43.0731, longitude: -89.4012)

    private static func fetchRide(_ id: UUID, from swiftDataStack: SwiftDataStack) throws -> Ride {
        let context = ModelContext(swiftDataStack.container)
        var descriptor = FetchDescriptor<Ride>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try #require(try context.fetch(descriptor).first)
    }

    /// One in-memory intent store shared between the ride and the simulated relaunch,
    /// standing in for the real JSON file that outlives the process.
    private static func makeRideStore(
        persistenceClient: PersistenceClient,
        documentsDirectory: URL,
        rideEndIntentClient: RideEndIntentClient,
        mapSnapshotClient: MapSnapshotClient = .testValue,
        healthKitClient: HealthKitClient = .testValue,
        date: DateGenerator = .constant(testDate)
    ) -> TestStoreOf<ActiveRideFeature> {
        let store = TestStore(
            initialState: ActiveRideFeature.State(recordingState: .idle)
        ) {
            ActiveRideFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.date = date
            $0.uuid = .incrementing
            $0.hapticsClient = .testValue
            $0.audioClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.locationClient = .testValue
            $0.persistenceClient = persistenceClient
            $0.gpxDocumentsDirectory = documentsDirectory
            $0.rideEndIntentClient = rideEndIntentClient
            $0.mapSnapshotClient = mapSnapshotClient
            $0.healthKitClient = healthKitClient
        }
        store.exhaustivity = .off
        return store
    }

    /// Stands in for MapKit's tiles (#177): counts renders and answers each appearance with
    /// its own bytes, so a test can tell the two stored images apart.
    private static func countingSnapshots(_ renders: LockIsolated<Int>) -> MapSnapshotClient {
        MapSnapshotClient { _, _, style in
            renders.withValue { $0 += 1 }
            return Data(style == .dark ? "dark".utf8 : "light".utf8)
        }
    }

    /// Start → record a few seconds → pause → finish → confirm, then drain the
    /// fire-and-forget ride-end pipeline. Three ticks is deliberately short of the 30-tick
    /// checkpoint, so nothing reaches persistence until the final flush.
    ///
    /// `until` is the caller's evidence that the fire-and-forget pipeline has finished.
    /// It is required because `skipInFlightEffects` **cancels** in-flight effects rather
    /// than awaiting them: without observing the pipeline first, a loaded machine kills
    /// it mid-flight and the assertions below see a half-ended ride. CI on 2026-09-07
    /// caught exactly that here (`pending.gpxFileURL → nil`).
    ///
    /// `speedMPS`, when given, is held for the recorded seconds so the ride covers distance.
    private static func runRideToEnd(
        _ store: TestStoreOf<ActiveRideFeature>,
        speedMPS: Double? = nil,
        until pipelineFinished: @escaping @Sendable (UUID) -> Bool
    ) async -> UUID {
        await store.send(.task)
        let rideId = store.state.rideId

        await store.send(.locationUpdated(LocationUpdate(
            coordinate: coordinate, altitude: 12, speed: 5,
            horizontalAccuracy: 5, heading: 90, timestamp: testDate
        )))
        if let speedMPS {
            await store.send(.speed(.gpsSpeedReceived(speedMPS)))
        }
        for _ in 1...3 {
            await store.send(.elapsedTick)
        }

        await store.send(.pauseTapped)
        await store.send(.finishTapped)
        await store.send(.finishAlert(.presented(.confirmFinish)))
        await expectEventually { pipelineFinished(rideId) }
        await store.skipInFlightEffects(strict: false)
        await store.finish(timeout: effectDrainTimeout)
        return rideId
    }

    private static func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    // MARK: - Paths that degrade acceptably

    @Test("a flushTrackPoints failure at ride end still ends the ride and still writes a GPX file, missing only the unflushed points")
    func flushFailureTruncatesExportButStillEndsRide() async throws {
        let (liveClient, swiftDataStack) = PersistenceClientTests.makeLiveClient()
        var client = liveClient
        client.flushTrackPoints = { _ in throw WriteFailed() }

        let tempDir = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let rideEndIntent = RideEndIntentClient.inMemory()

        let store = Self.makeRideStore(persistenceClient: client, documentsDirectory: tempDir, rideEndIntentClient: rideEndIntent)
        // finalizeRide still succeeds here, so the ride reaching `.ended` is the signal.
        let rideId = await Self.runRideToEnd(store) {
            fetchRideIfPresent($0, from: swiftDataStack)?.recordingState == .ended
        }

        // The ride still closes out — a lost flush must not strand it out of `.ended`.
        let ride = try Self.fetchRide(rideId, from: swiftDataStack)
        #expect(ride.recordingState == .ended)
        #expect(ride.endedAt != nil)

        // And a file is still produced, just without the points that never landed.
        let gpxURL = try #require(ride.gpxFileURL)
        let parsed = try GPXParsing.parse(try String(contentsOf: gpxURL, encoding: .utf8))
        #expect(parsed.trackPoints.isEmpty)
        #expect(try await client.fetchTrackPoints(rideId).isEmpty)

        // finalizeRide succeeded, so the end intent is discharged.
        #expect(rideEndIntent.load() == nil)
    }

    @Test("a GPX export failure at ride end still ends the ride, with a nil gpxFileURL")
    func exportFailureStillEndsRideWithNilURL() async throws {
        let (liveClient, swiftDataStack) = PersistenceClientTests.makeLiveClient()
        var client = liveClient
        // GPXExporter.generate reads the ride's metadata first, so this is the seam that
        // makes the export — and only the export — fail.
        client.fetchRide = { _ in throw PersistenceError.rideNotFound }

        let tempDir = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let rideEndIntent = RideEndIntentClient.inMemory()

        let store = Self.makeRideStore(persistenceClient: client, documentsDirectory: tempDir, rideEndIntentClient: rideEndIntent)
        // Only the export fails, so finalizeRide still lands the ride in `.ended`.
        let rideId = await Self.runRideToEnd(store) {
            fetchRideIfPresent($0, from: swiftDataStack)?.recordingState == .ended
        }

        let ride = try Self.fetchRide(rideId, from: swiftDataStack)
        #expect(ride.recordingState == .ended)
        #expect(ride.endedAt != nil)
        #expect(ride.gpxFileURL == nil)
        #expect(rideEndIntent.load() == nil)
    }

    // MARK: - Map thumbnail (#177)

    @Test("a finished ride gets its map thumbnail, both appearances, rendered once after it is finalized")
    func finishedRideGetsItsThumbnail() async throws {
        let (client, swiftDataStack) = PersistenceClientTests.makeLiveClient()
        let tempDir = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let renders = LockIsolated(0)

        let store = Self.makeRideStore(
            persistenceClient: client, documentsDirectory: tempDir,
            rideEndIntentClient: .inMemory(), mapSnapshotClient: Self.countingSnapshots(renders)
        )
        let rideId = await Self.runRideToEnd(store) {
            fetchRideIfPresent($0, from: swiftDataStack)?.mapThumbnailDark != nil
        }

        let ride = try Self.fetchRide(rideId, from: swiftDataStack)
        #expect(ride.recordingState == .ended)
        #expect(ride.mapThumbnailLight == Data("light".utf8))
        #expect(ride.mapThumbnailDark == Data("dark".utf8))
        // One light, one dark: captured once, not per list render.
        #expect(renders.value == 2)
    }

    @Test("a map thumbnail failure at ride end leaves the ride ended with its GPX, and the next launch captures it")
    func thumbnailFailureStillEndsRide() async throws {
        let (client, swiftDataStack) = PersistenceClientTests.makeLiveClient()
        let tempDir = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let rideEndIntent = RideEndIntentClient.inMemory()
        let attempts = LockIsolated(0)

        let store = Self.makeRideStore(
            persistenceClient: client, documentsDirectory: tempDir, rideEndIntentClient: rideEndIntent,
            mapSnapshotClient: MapSnapshotClient { _, _, _ in
                attempts.withValue { $0 += 1 }
                throw MapSnapshotError.unavailable
            }
        )
        // The render is the last step, so an attempt at it means everything before it ran.
        let rideId = await Self.runRideToEnd(store) { _ in attempts.value > 0 }

        let ride = try Self.fetchRide(rideId, from: swiftDataStack)
        #expect(ride.recordingState == .ended)
        #expect(ride.endedAt != nil)
        #expect(ride.gpxFileURL != nil)
        #expect(ride.mapThumbnailLight == nil)
        #expect(ride.mapThumbnailDark == nil)
        #expect(rideEndIntent.load() == nil)

        // Next launch, back online: the thumbnail is late, not lost.
        let appStore = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.date = .constant(Self.testDate.addingTimeInterval(600))
            $0.uuid = .incrementing
            $0.bleCSCClient = .testValue
            $0.bleHRClient = .testValue
            $0.variaRadarClient = .testValue
            $0.locationClient = .testValue
            $0.hapticsClient = .testValue
            $0.screenClient = .testValue
            $0.persistenceClient = client
            $0.gpxDocumentsDirectory = tempDir
            $0.rideEndIntentClient = rideEndIntent
            $0.mapSnapshotClient = Self.countingSnapshots(LockIsolated(0))
        }
        appStore.exhaustivity = .off
        await appStore.send(.task)
        await appStore.finish(timeout: effectDrainTimeout)

        let relaunched = try Self.fetchRide(rideId, from: swiftDataStack)
        #expect(relaunched.mapThumbnailLight == Data("light".utf8))
        #expect(relaunched.mapThumbnailDark == Data("dark".utf8))
    }

    // MARK: - Apple Health workout (#250)

    @Test("a finished ride is written to Apple Health once, after it is finalized, with the persisted ride's start, end and distance")
    func finishedRideIsWrittenToHealthAfterFinalize() async throws {
        let (client, swiftDataStack) = PersistenceClientTests.makeLiveClient()
        let tempDir = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let written = LockIsolated<[RideWorkout]>([])
        // Read inside the write, not after it: what matters is whether the ride was already
        // durably ended at the moment its workout left for Apple Health.
        let endedAtWhenWritten = LockIsolated<Date?>(nil)

        // A clock that moves, one second per read: with a constant one the ride starts and ends
        // at the same instant, and a workout built from the wrong one of the two still matches.
        let reads = LockIsolated(0.0)
        let movingClock = DateGenerator {
            reads.withValue { $0 += 1; return Self.testDate.addingTimeInterval($0) }
        }
        let store = Self.makeRideStore(
            persistenceClient: client, documentsDirectory: tempDir, rideEndIntentClient: .inMemory(),
            healthKitClient: .mock(onSaveWorkout: { workout in
                endedAtWhenWritten.setValue(fetchRideIfPresent(workout.rideId, from: swiftDataStack)?.endedAt)
                written.withValue { $0.append(workout) }
            }),
            date: movingClock
        )
        let rideId = await Self.runRideToEnd(store, speedMPS: 5) { _ in !written.value.isEmpty }

        let ride = try Self.fetchRide(rideId, from: swiftDataStack)
        // Moving, so the distance comparison below can't pass on two zeros.
        #expect(ride.distanceMeters > 0)
        let workout = try #require(written.value.first)
        let endedAt = try #require(ride.endedAt)
        #expect(written.value.count == 1)
        #expect(endedAtWhenWritten.value == endedAt)
        #expect(ride.startedAt < endedAt)
        #expect(workout == RideWorkout(
            rideId: rideId,
            startedAt: ride.startedAt,
            endedAt: endedAt,
            distanceMeters: ride.distanceMeters
        ))
    }

    @Test("an Apple Health workout write failure at ride end still ends the ride, and the steps after it still run")
    func workoutWriteFailureStillEndsRide() async throws {
        let (client, swiftDataStack) = PersistenceClientTests.makeLiveClient()
        let tempDir = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let rideEndIntent = RideEndIntentClient.inMemory()
        let attempts = LockIsolated(0)
        let renders = LockIsolated(0)

        let store = Self.makeRideStore(
            persistenceClient: client, documentsDirectory: tempDir, rideEndIntentClient: rideEndIntent,
            mapSnapshotClient: Self.countingSnapshots(renders),
            // What a revoked permission looks like from here.
            healthKitClient: .mock(onSaveWorkout: { _ in
                attempts.withValue { $0 += 1 }
                throw WriteFailed()
            })
        )
        // The thumbnail comes after the workout, so its second render means the pipeline
        // carried on past the failure to its end.
        let rideId = await Self.runRideToEnd(store) { _ in renders.value == 2 }

        let ride = try Self.fetchRide(rideId, from: swiftDataStack)
        #expect(attempts.value == 1)
        #expect(ride.recordingState == .ended)
        #expect(ride.endedAt != nil)
        #expect(ride.gpxFileURL != nil)
        #expect(ride.mapThumbnailDark == Data("dark".utf8))
        #expect(rideEndIntent.load() == nil)
    }

    // MARK: - The path that did not degrade acceptably

    @Test("a finalizeRide failure records the end intent, and the next launch closes the ride out instead of resuming it")
    func finalizeFailureIsRecoveredAtLaunchRatherThanResumed() async throws {
        let (liveClient, swiftDataStack) = PersistenceClientTests.makeLiveClient()
        var failingClient = liveClient
        failingClient.finalizeRide = { _, _, _, _ in throw WriteFailed() }

        let tempDir = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let rideEndIntent = RideEndIntentClient.inMemory()

        let renders = LockIsolated(0)
        let workoutWrites = LockIsolated(0)
        let store = Self.makeRideStore(
            persistenceClient: failingClient, documentsDirectory: tempDir,
            rideEndIntentClient: rideEndIntent, mapSnapshotClient: Self.countingSnapshots(renders),
            healthKitClient: .mock(onSaveWorkout: { _ in workoutWrites.withValue { $0 += 1 } })
        )
        // finalizeRide is the thing failing here, so the ride never reaches `.ended`.
        // The recorded intent, carrying the GPX written before the failure, is the
        // pipeline's observable end state instead.
        let rideId = await Self.runRideToEnd(store) { _ in rideEndIntent.load()?.gpxFileURL != nil }

        // The write failed, so the row still looks like a ride in progress — this is the
        // state that used to be resumed.
        let strandedRide = try Self.fetchRide(rideId, from: swiftDataStack)
        #expect(strandedRide.endedAt == nil)
        // A ride that isn't durably ended never reaches Apple Health (#250).
        #expect(workoutWrites.value == 0)
        let summary = try #require(try await liveClient.fetchResumableRide())
        #expect(summary.rideId == rideId)

        // But the rider's intent to end it survived, in storage the failed write cannot
        // reach — including the URL of the GPX that was written before the failure.
        let pending = try #require(rideEndIntent.load())
        #expect(pending.rideId == rideId)
        #expect(pending.endedAt == Self.testDate)
        #expect(pending.gpxFileURL != nil)

        // Relaunch: same persistence, same storage, a working finalize.
        let appStore = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.date = .constant(Self.testDate.addingTimeInterval(600))
            $0.uuid = .incrementing
            $0.bleCSCClient = .testValue
            $0.bleHRClient = .testValue
            $0.variaRadarClient = .testValue
            $0.locationClient = .testValue
            $0.hapticsClient = .testValue
            $0.screenClient = .testValue
            $0.persistenceClient = liveClient
            $0.gpxDocumentsDirectory = tempDir
            $0.rideEndIntentClient = rideEndIntent
            $0.mapSnapshotClient = Self.countingSnapshots(renders)
        }
        appStore.exhaustivity = .off

        await appStore.send(.resumableRideFetched(summary))
        await appStore.finish(timeout: effectDrainTimeout)

        // The ride the rider already ended is not resumed.
        #expect(appStore.state.activeRide == nil)
        #expect(appStore.state.isDashboardPresented == false)

        // It is closed out instead, keeping the export that had already been written.
        let recovered = try Self.fetchRide(rideId, from: swiftDataStack)
        #expect(recovered.recordingState == .ended)
        #expect(recovered.endedAt == Self.testDate)
        #expect(recovered.gpxFileURL == pending.gpxFileURL)
        // And the thumbnail the failed finish never got to is captured now (#177) — only
        // now: one light and one dark in total. Counted at the end rather than checked for
        // zero after the ride store returns, which is before its finalize has even run.
        #expect(recovered.mapThumbnailLight == Data("light".utf8))
        #expect(recovered.mapThumbnailDark == Data("dark".utf8))
        #expect(renders.value == 2)

        // Intent discharged, and no longer resumable.
        #expect(rideEndIntent.load() == nil)
        #expect(try await liveClient.fetchResumableRide() == nil)
    }

    @Test("a stale marker for a different ride does not stop a genuinely interrupted ride from resuming")
    func staleMarkerDoesNotBlockAGenuineResume() async throws {
        let tempDir = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // A marker left by some other ride entirely — it must not be read as "this ride
        // is over" for the ride actually being recovered.
        let rideEndIntent = RideEndIntentClient.inMemory(
            initial: PendingRideEnd(rideId: UUID(), endedAt: Self.testDate, gpxFileURL: nil)
        )

        let interruptedSummary = RideSummaryUpdate(
            rideId: UUID(), recordingState: .active,
            durationSeconds: 120, distanceMeters: 800, averageSpeedMPS: 5, maxSpeedMPS: 9
        )

        let appStore = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.date = .constant(Self.testDate)
            $0.uuid = .incrementing
            $0.bleCSCClient = .testValue
            $0.bleHRClient = .testValue
            $0.variaRadarClient = .testValue
            $0.locationClient = .testValue
            $0.hapticsClient = .testValue
            $0.screenClient = .testValue
            $0.persistenceClient = .mock(resumableRide: interruptedSummary)
            $0.gpxDocumentsDirectory = tempDir
            $0.rideEndIntentClient = rideEndIntent
        }
        appStore.exhaustivity = .off

        await appStore.send(.resumableRideFetched(interruptedSummary))

        #expect(appStore.state.activeRide?.rideId == interruptedSummary.rideId)
        #expect(appStore.state.isDashboardPresented == true)

        // Tear the resumed ride's effects down through the real flow.
        await appStore.send(.activeRide(.pauseTapped))
        await appStore.send(.activeRide(.finishTapped))
        await appStore.send(.activeRide(.finishAlert(.presented(.confirmFinish))))
        await appStore.skipInFlightEffects(strict: false)
        await appStore.finish(timeout: effectDrainTimeout)
    }
}
