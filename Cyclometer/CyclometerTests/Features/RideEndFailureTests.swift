import ComposableArchitecture
import Foundation
import SwiftData
import Testing
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
        rideEndIntentClient: RideEndIntentClient
    ) -> TestStoreOf<ActiveRideFeature> {
        let store = TestStore(
            initialState: ActiveRideFeature.State(recordingState: .idle)
        ) {
            ActiveRideFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.date = .constant(testDate)
            $0.uuid = .incrementing
            $0.hapticsClient = .testValue
            $0.audioClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.locationClient = .testValue
            $0.persistenceClient = persistenceClient
            $0.gpxDocumentsDirectory = documentsDirectory
            $0.rideEndIntentClient = rideEndIntentClient
        }
        store.exhaustivity = .off
        return store
    }

    /// Start → record a few seconds → pause → finish → confirm, then drain the
    /// fire-and-forget ride-end pipeline. Three ticks is deliberately short of the 30-tick
    /// checkpoint, so nothing reaches persistence until the final flush.
    private static func runRideToEnd(_ store: TestStoreOf<ActiveRideFeature>) async -> UUID {
        await store.send(.task)
        let rideId = store.state.rideId

        await store.send(.locationUpdated(LocationUpdate(
            coordinate: coordinate, altitude: 12, speed: 5,
            horizontalAccuracy: 5, heading: 90, timestamp: testDate
        )))
        for _ in 1...3 {
            await store.send(.elapsedTick)
        }

        await store.send(.pauseTapped)
        await store.send(.finishTapped)
        await store.send(.finishAlert(.presented(.confirmFinish)))
        await store.skipInFlightEffects(strict: false)
        await store.finish(timeout: .seconds(5))
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
        let rideId = await Self.runRideToEnd(store)

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
        let rideId = await Self.runRideToEnd(store)

        let ride = try Self.fetchRide(rideId, from: swiftDataStack)
        #expect(ride.recordingState == .ended)
        #expect(ride.endedAt != nil)
        #expect(ride.gpxFileURL == nil)
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

        let store = Self.makeRideStore(persistenceClient: failingClient, documentsDirectory: tempDir, rideEndIntentClient: rideEndIntent)
        let rideId = await Self.runRideToEnd(store)

        // The write failed, so the row still looks like a ride in progress — this is the
        // state that used to be resumed.
        let strandedRide = try Self.fetchRide(rideId, from: swiftDataStack)
        #expect(strandedRide.endedAt == nil)
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
        }
        appStore.exhaustivity = .off

        await appStore.send(.resumableRideFetched(summary))
        await appStore.finish(timeout: .seconds(5))

        // The ride the rider already ended is not resumed.
        #expect(appStore.state.activeRide == nil)
        #expect(appStore.state.isDashboardPresented == false)

        // It is closed out instead, keeping the export that had already been written.
        let recovered = try Self.fetchRide(rideId, from: swiftDataStack)
        #expect(recovered.recordingState == .ended)
        #expect(recovered.endedAt == Self.testDate)
        #expect(recovered.gpxFileURL == pending.gpxFileURL)

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
        await appStore.finish(timeout: .seconds(5))
    }
}
