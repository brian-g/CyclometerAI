import ComposableArchitecture
import Foundation
import SwiftData
import Testing
@testable import Cyclometer

/// End-to-end coverage for #174: the full ride lifecycle against **real**
/// persistence and GPX export (not mocks), proving the actual pipeline —
/// flush → GPXExporter.generate → finalizeRide — produces a valid file on disk
/// and a correctly-updated `Ride` row, not just that the right dependency calls
/// happen. `ActiveRideFeatureTests`/`PersistenceClientTests`/`GPXExporterTests`
/// already cover each stage in isolation; this suite is the seam between them.
@MainActor
@Suite("Ride recording — full lifecycle")
struct RideRecordingTests {
    private static let testDate = Date(timeIntervalSince1970: 1_000_000)

    private static func fetchRide(_ id: UUID, from swiftDataStack: SwiftDataStack) throws -> Ride {
        let context = ModelContext(swiftDataStack.container)
        var descriptor = FetchDescriptor<Ride>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try #require(try context.fetch(descriptor).first)
    }

    @Test("idle → active → paused → active → paused → ended produces a valid GPX file and a finalized Ride row")
    func fullLifecycleProducesValidGPXFile() async throws {
        let (persistenceClient, swiftDataStack) = PersistenceClientTests.makeLiveClient()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let store = TestStore(
            initialState: ActiveRideFeature.State(recordingState: .idle)
        ) {
            ActiveRideFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.date = .constant(Self.testDate)
            $0.uuid = .incrementing
            $0.hapticsClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.locationClient = .testValue
            $0.persistenceClient = persistenceClient
            $0.gpxDocumentsDirectory = tempDir
        }
        // Long-lived `.task` effects (1 Hz timer, HR, radar, location) never complete
        // on their own — same non-exhaustive shape as
        // `ActiveRideFeatureStateMachineTests.taskTransitionsIdleToActive`.
        store.exhaustivity = .off

        await store.send(.task)
        #expect(store.state.recordingState == .active)
        let rideId = store.state.rideId

        // active → paused → active → paused: `finishTapped` only presents its alert
        // from `.paused` (`ActiveRideFeature.swift`'s `finishTapped` guard), so the
        // acceptance criterion's "active" revisit needs a second pause before ending.
        await store.send(.pauseTapped)
        #expect(store.state.recordingState == .paused)
        await store.send(.resumeTapped)
        #expect(store.state.recordingState == .active)
        await store.send(.pauseTapped)
        #expect(store.state.recordingState == .paused)

        await store.send(.finishTapped)
        #expect(store.state.finishAlert != nil)
        await store.send(.finishAlert(.presented(.confirmFinish)))
        #expect(store.state.recordingState == .ended)

        // The flush → GPXExporter.generate → finalizeRide pipeline runs as an
        // unreceived `.run` effect (no delegate action to `store.receive`), so
        // draining in-flight effects is the only way to know it's actually done
        // before asserting against SwiftData/disk below.
        await store.skipInFlightEffects(strict: false)
        await store.finish(timeout: .seconds(5))

        let ride = try Self.fetchRide(rideId, from: swiftDataStack)
        #expect(ride.recordingState == .ended)
        #expect(ride.endedAt != nil)
        let gpxURL = try #require(ride.gpxFileURL)
        #expect(gpxURL.path.hasPrefix(tempDir.path))
        #expect(FileManager.default.fileExists(atPath: gpxURL.path))
        let contents = try String(contentsOf: gpxURL, encoding: .utf8)
        #expect(contents.contains("<gpx"))
        #expect(contents.contains("<trk>"))

        let parser = XMLParser(data: try Data(contentsOf: gpxURL))
        #expect(parser.parse())
    }

    /// #175: a kill mid-ride, simulated by letting a `TestStore` go out of scope
    /// with no teardown — only its in-memory `RideDataBuffer` (a fresh actor per
    /// dependency scope, `RideDataBuffer.swift`) is lost with it, exactly like a
    /// real process kill; the shared, real `persistenceClient`'s CoreData/SwiftData
    /// survive. A "relaunch" is a second `TestStore` built from
    /// `ActiveRideFeature.State(resuming:)` against that same persistence.
    @Test("kill mid-ride and relaunch resumes the same rideId, carrying aggregates and track points forward")
    func killAndRelaunchResumesRide() async throws {
        let (persistenceClient, swiftDataStack) = PersistenceClientTests.makeLiveClient()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coordinateA = Coordinate(latitude: 37.0, longitude: -122.0)
        let coordinateB = Coordinate(latitude: 38.0, longitude: -123.0)

        let rideId: UUID
        do {
            let firstStore = TestStore(
                initialState: ActiveRideFeature.State(recordingState: .idle)
            ) {
                ActiveRideFeature()
            } withDependencies: {
                $0.continuousClock = TestClock()
                $0.date = .constant(Self.testDate)
                $0.uuid = .incrementing
                $0.hapticsClient = .testValue
                $0.variaRadarClient = .testValue
                $0.bleHRClient = .testValue
                $0.locationClient = .testValue
                $0.persistenceClient = persistenceClient
                $0.gpxDocumentsDirectory = tempDir
            }
            firstStore.exhaustivity = .off

            await firstStore.send(.task)
            rideId = firstStore.state.rideId

            await firstStore.send(.locationUpdated(LocationUpdate(
                coordinate: coordinateA, altitude: 10, speed: 5, horizontalAccuracy: 5,
                heading: 90, timestamp: Self.testDate
            )))
            // Crosses one 30-tick checkpoint (aggregates + track points flushed at
            // tick 30), then keeps going 5 more ticks whose track points sit
            // unflushed in this store's own RideDataBuffer when it "dies" below —
            // the accepted one-checkpoint-window data loss.
            for _ in 1...35 {
                await firstStore.send(.elapsedTick)
            }
            // firstStore goes out of scope here — no `.finish()`, no explicit
            // teardown. Simulates the kill.
        }

        let resumable = try #require(try await persistenceClient.fetchResumableRide())
        #expect(resumable.rideId == rideId)
        #expect(resumable.durationSeconds == 30)

        let secondStore = TestStore(
            initialState: ActiveRideFeature.State(resuming: resumable)
        ) {
            ActiveRideFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.date = .constant(Self.testDate.addingTimeInterval(60))
            $0.uuid = .incrementing
            $0.hapticsClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.locationClient = .testValue
            $0.persistenceClient = persistenceClient
            $0.gpxDocumentsDirectory = tempDir
        }
        secondStore.exhaustivity = .off

        await secondStore.send(.task)
        #expect(secondStore.state.rideId == rideId)
        #expect(secondStore.state.recordingState == .active)

        await secondStore.send(.locationUpdated(LocationUpdate(
            coordinate: coordinateB, altitude: 12, speed: 6, horizontalAccuracy: 5,
            heading: 90, timestamp: Self.testDate.addingTimeInterval(60)
        )))
        for _ in 1...5 {
            await secondStore.send(.elapsedTick)
        }

        await secondStore.send(.pauseTapped)
        await secondStore.send(.finishTapped)
        await secondStore.send(.finishAlert(.presented(.confirmFinish)))
        await secondStore.skipInFlightEffects(strict: false)
        await secondStore.finish(timeout: .seconds(5))

        let ride = try Self.fetchRide(rideId, from: swiftDataStack)
        #expect(ride.recordingState == .ended)
        #expect(ride.endedAt != nil)
        // Built on the seeded base rather than reset to zero: more elapsed time
        // than the pre-kill checkpoint alone recorded.
        #expect(ride.durationSeconds == 35)

        let gpxURL = try #require(ride.gpxFileURL)
        let contents = try String(contentsOf: gpxURL, encoding: .utf8)
        #expect(contents.contains(String(format: "lat=\"%.7f\" lon=\"%.7f\"", coordinateA.latitude, coordinateA.longitude)))
        #expect(contents.contains(String(format: "lat=\"%.7f\" lon=\"%.7f\"", coordinateB.latitude, coordinateB.longitude)))
    }

    @Test("an .ended ride is never returned as resumable")
    func endedRideIsNeverResumed() async throws {
        let (persistenceClient, _) = PersistenceClientTests.makeLiveClient()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let store = TestStore(
            initialState: ActiveRideFeature.State(recordingState: .idle)
        ) {
            ActiveRideFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.date = .constant(Self.testDate)
            $0.uuid = .incrementing
            $0.hapticsClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.locationClient = .testValue
            $0.persistenceClient = persistenceClient
            $0.gpxDocumentsDirectory = tempDir
        }
        store.exhaustivity = .off

        await store.send(.task)
        await store.send(.pauseTapped)
        await store.send(.finishTapped)
        await store.send(.finishAlert(.presented(.confirmFinish)))
        await store.skipInFlightEffects(strict: false)
        await store.finish(timeout: .seconds(5))

        #expect(try await persistenceClient.fetchResumableRide() == nil)
    }
}
