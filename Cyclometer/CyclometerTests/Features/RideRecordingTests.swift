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
}
