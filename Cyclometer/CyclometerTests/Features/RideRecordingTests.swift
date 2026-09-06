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

    // MARK: - Vehicle passes through the whole pipeline

    /// Reaches 4 m — inside `VehiclePassDetector.passProximityMetres` — so this vehicle
    /// genuinely overtook the rider and must produce an event.
    private static let approachingVehicle = RadarTarget(
        id: VariaRadarClient.vehicleSlotIDs[0], relativeVelocityMPS: 8, rangeMetres: 4, threatLevel: .warning
    )
    /// Closing just as hard, tracked just as long, disappearing on the very same tick —
    /// but never nearer than 60 m, so the detector must reject it as a vehicle that
    /// never reached the rider. Range is the only thing separating the two.
    ///
    /// It used to be separated by a *negative* closing speed instead, which the Varia's
    /// unsigned wire byte cannot produce — so this pair only ever exercised a
    /// discriminator no real ride could reach (#207).
    private static let lostVehicle = RadarTarget(
        id: VariaRadarClient.vehicleSlotIDs[1], relativeVelocityMPS: 8, rangeMetres: 60, threatLevel: .warning
    )

    /// The exporter's AlertLevel spelling. That this is the mapping GPXExporter
    /// actually emits is pinned by `GPXExporterTests.alertLevelStrings`; here it only
    /// needs to name the level the persisted event carries, so the two can be compared.
    private static func gpxAlertLevel(_ level: AlertLevel) -> String {
        switch level {
        case .clear: "clear"
        case .advisory: "advisory"
        case .caution: "caution"
        case .danger: "danger"
        }
    }

    private static func location(_ coordinate: Coordinate, altitude: Double, at time: Date) -> LocationUpdate {
        LocationUpdate(
            coordinate: coordinate, altitude: altitude, speed: 5,
            horizontalAccuracy: 5, heading: 90, timestamp: time
        )
    }

    /// The seam #176 is actually about: the detector is covered as a pure function,
    /// persistence via mocks, and the exporter with hand-built DTOs — but nothing
    /// joined them, so a break anywhere along
    /// `radarTargetsUpdated → VehiclePassDetector → appendVehiclePassEvents →
    /// GPXExporter → <wpt>` was invisible. This drives that whole chain once and
    /// checks all three records of the ride agree.
    ///
    /// Note `date` is mutated between sends rather than pinned with `.constant`, as
    /// the other tests in this suite do: `VehiclePassDetector` needs the vehicle
    /// tracked >= 2s *and* absent >= 2s, both measured off `date.now`, so under a
    /// frozen clock a pass can never fire at all. Same idiom as
    /// `ActiveRideFeatureVehiclePassPersistenceTests.sendOvertake`.
    @Test("a ride with vehicle passes agrees across TrackPoints, VehiclePassEvents and the written GPX")
    func vehiclePassesAgreeAcrossPersistenceAndGPX() async throws {
        let (persistenceClient, swiftDataStack) = PersistenceClientTests.makeLiveClient()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coordinateA = Coordinate(latitude: 43.0731, longitude: -89.4012)
        let coordinateB = Coordinate(latitude: 43.0745, longitude: -89.4030)

        let store = TestStore(
            initialState: ActiveRideFeature.State(recordingState: .idle)
        ) {
            ActiveRideFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.date = .constant(Self.testDate)
            $0.uuid = .incrementing
            $0.hapticsClient = .testValue
            $0.audioClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.locationClient = .testValue
            $0.persistenceClient = persistenceClient
            $0.gpxDocumentsDirectory = tempDir
        }
        store.exhaustivity = .off

        await store.send(.task)
        let rideId = store.state.rideId

        // A rider position must exist before the pass is confirmed — the detector
        // drops an event whose last sighting had no GPS fix.
        await store.send(.locationUpdated(Self.location(coordinateA, altitude: 12, at: Self.testDate)))
        await store.send(.elapsedTick)

        // Both vehicles are tracked together and disappear together, so the only
        // thing separating them is how close each came to the rider.
        await store.send(.radarTargetsUpdated([Self.approachingVehicle, Self.lostVehicle]))

        store.dependencies.date.now = Self.testDate.addingTimeInterval(2)
        await store.send(.radarTargetsUpdated([Self.approachingVehicle, Self.lostVehicle]))
        await store.send(.elapsedTick)

        store.dependencies.date.now = Self.testDate.addingTimeInterval(4)
        await store.send(.radarTargetsUpdated([]))
        await store.receive(\.vehiclePassEventsPersisted)
        await store.send(.elapsedTick)

        store.dependencies.date.now = Self.testDate.addingTimeInterval(6)
        await store.send(.locationUpdated(Self.location(coordinateB, altitude: 15, at: Self.testDate.addingTimeInterval(6))))
        await store.send(.elapsedTick)

        #expect(store.state.vehiclePassCount == 1)

        await store.send(.pauseTapped)
        await store.send(.finishTapped)
        await store.send(.finishAlert(.presented(.confirmFinish)))
        await store.skipInFlightEffects(strict: false)
        await store.finish(timeout: .seconds(5))

        // --- The three records of this ride, read back independently ---
        let persistedPoints = try await persistenceClient.fetchTrackPoints(rideId)
        let persistedEvents = try await persistenceClient.fetchVehiclePassEvents(rideId)
        let ride = try Self.fetchRide(rideId, from: swiftDataStack)
        let gpxURL = try #require(ride.gpxFileURL)
        let parsed = try GPXParsing.parse(try String(contentsOf: gpxURL, encoding: .utf8))

        // Exactly one pass survived detection, and it is the approaching vehicle's.
        #expect(persistedEvents.count == 1)
        #expect(ride.vehiclePassCount == 1)
        #expect(parsed.waypoints.count == 1)

        // Counts agree: every recorded track point reached the file, and no extras.
        #expect(persistedPoints.count == 4)
        #expect(parsed.trackPoints.count == persistedPoints.count)

        // Field-level agreement between what was persisted and what was written.
        // Compared by value, not identity — VehiclePassEventDTO carries no id, so
        // nothing survives the persistence round trip to match on.
        let event = try #require(persistedEvents.first)
        let waypoint = try #require(parsed.waypoints.first)
        #expect(waypoint.latitude == event.latitude)
        #expect(waypoint.longitude == event.longitude)
        #expect(waypoint.riderSpeedKph == event.riderSpeedKph)
        #expect(waypoint.type == "vehiclePass")
        // The exact level is AlertLevelTests' business; what matters here is that the
        // file reports the same one that was persisted.
        #expect(waypoint.alertLevel == Self.gpxAlertLevel(event.alertLevelAtPass))

        // The pass is positioned at the rider's location as of the last sighting
        // (coordinate A), not wherever the rider had moved to by confirmation time.
        #expect(event.latitude == coordinateA.latitude)
        #expect(event.longitude == coordinateA.longitude)

        for (index, point) in persistedPoints.enumerated() {
            #expect(parsed.trackPoints[index].latitude == point.latitude)
            #expect(parsed.trackPoints[index].longitude == point.longitude)
            #expect(parsed.trackPoints[index].elevation == point.altitudeMeters)
        }

        // The rider moved partway through, and the file records both positions.
        #expect(parsed.trackPoints.contains { $0.latitude == coordinateA.latitude })
        #expect(parsed.trackPoints.contains { $0.latitude == coordinateB.latitude })
    }
}
