import ComposableArchitecture
import Foundation
import SwiftData
import Testing
@testable import Cyclometer

@Suite("PersistenceClient")
struct PersistenceClientTests {

    /// Fresh in-memory CoreData + SwiftData stacks per test — no shared state, no disk I/O.
    /// The SwiftData stack is returned alongside the client so Ride tests can also
    /// fetch directly against it when asserting on state the client doesn't expose
    /// as a DTO (e.g. `recordingState`).
    static func makeLiveClient() -> (client: PersistenceClient, swiftDataStack: SwiftDataStack) {
        let coreDataStack = CoreDataStack(inMemory: true)
        let swiftDataStack = SwiftDataStack(inMemory: true)
        let client = PersistenceClient.live(
            coreDataContainer: coreDataStack.container,
            modelContainer: swiftDataStack.container
        )
        return (client, swiftDataStack)
    }

    @Test("flushed points are queryable by rideId, ordered by timestamp")
    func flushAndFetchRoundTrip() async throws {
        let (client, _) = Self.makeLiveClient()
        let rideId = UUID()
        let otherRideId = UUID()
        let base = Date()

        let points = (0..<5).map { offset in
            TrackPointDTO(
                rideId: rideId,
                timestamp: base.addingTimeInterval(TimeInterval(offset)),
                latitude: 37.0 + Double(offset),
                longitude: -122.0,
                altitudeMeters: 10,
                horizontalAccuracyMeters: 5,
                speedMPS: 4.5,
                speedSource: .gps,
                heartRateBPM: 140,
                heartRateSource: .bleHR,
                cadenceRPM: 85,
                powerWatts: nil
            )
        }
        let otherRidePoint = TrackPointDTO(
            rideId: otherRideId,
            timestamp: base,
            latitude: 0,
            longitude: 0,
            altitudeMeters: 0,
            horizontalAccuracyMeters: 0,
            speedMPS: nil,
            speedSource: .none,
            heartRateBPM: nil,
            heartRateSource: .none,
            cadenceRPM: nil,
            powerWatts: nil
        )

        try await client.flushTrackPoints(points.shuffled() + [otherRidePoint])

        let fetched = try await client.fetchTrackPoints(rideId)
        #expect(fetched.count == 5)
        #expect(fetched.map(\.rideId) == Array(repeating: rideId, count: 5))
        #expect(fetched.map(\.timestamp) == points.map(\.timestamp))
    }

    @Test("nil sensor fields round-trip as nil, not as their CoreData sentinel value")
    func sentinelFieldsRoundTripAsNil() async throws {
        let (client, _) = Self.makeLiveClient()
        let rideId = UUID()
        let point = TrackPointDTO(
            rideId: rideId,
            timestamp: Date(),
            latitude: 1,
            longitude: 2,
            altitudeMeters: 3,
            horizontalAccuracyMeters: 4,
            speedMPS: nil,
            speedSource: .none,
            heartRateBPM: nil,
            heartRateSource: .none,
            cadenceRPM: nil,
            powerWatts: nil
        )

        try await client.flushTrackPoints([point])

        let fetched = try await client.fetchTrackPoints(rideId)
        #expect(fetched.count == 1)
        #expect(fetched[0].speedMPS == nil)
        #expect(fetched[0].heartRateBPM == nil)
        #expect(fetched[0].cadenceRPM == nil)
        #expect(fetched[0].powerWatts == nil)
    }

    @Test("fetchTrackPoints for an unknown rideId returns empty, not an error")
    func fetchUnknownRideIdIsEmpty() async throws {
        let (client, _) = Self.makeLiveClient()
        let fetched = try await client.fetchTrackPoints(UUID())
        #expect(fetched.isEmpty)
    }

    @Test("testValue never persists or returns data")
    func testValueIsInert() async throws {
        let client = PersistenceClient.testValue
        try await client.flushTrackPoints([
            TrackPointDTO(rideId: UUID(), timestamp: Date(), latitude: 0, longitude: 0, altitudeMeters: 0, horizontalAccuracyMeters: 0, speedSource: .none, heartRateSource: .none)
        ])
        #expect(try await client.fetchTrackPoints(UUID()).isEmpty)
        #expect(try await client.fetchRide(UUID()) == RideExportMetadata(title: "", startedAt: .init(timeIntervalSince1970: 0)))
        #expect(try await client.fetchVehiclePassEvents(UUID()).isEmpty)
        #expect(try await client.fetchResumableRide() == nil)
        try await client.createRide(UUID(), Date())
        let update = RideSummaryUpdate(rideId: UUID(), durationSeconds: 0, distanceMeters: 0, averageSpeedMPS: 0, maxSpeedMPS: 0)
        try await client.updateRideSummary(update)
        try await client.finalizeRide(UUID(), Date(), update, nil)
        try await client.appendVehiclePassEvents([VehiclePassEventDTO(
            rideId: UUID(), timestamp: Date(), latitude: 0, longitude: 0,
            alertLevelAtPass: .clear, riderSpeedKph: 0, estimatedPassSpeedKph: nil
        )])
    }

    @Test("mock returns exactly what it is scripted with, and reports flushed points")
    func mockReturnsScriptedValues() async throws {
        let rideId = UUID()
        let scripted = [TrackPointDTO(rideId: rideId, timestamp: Date(), latitude: 1, longitude: 1, altitudeMeters: 0, horizontalAccuracyMeters: 0, speedSource: .gps, heartRateSource: .bleHR)]
        let scriptedRideMetadata = RideExportMetadata(title: "Evening Ride", startedAt: Date())
        let scriptedPassEvents = [VehiclePassEventDTO(
            rideId: rideId, timestamp: Date(), latitude: 3, longitude: 4,
            alertLevelAtPass: .advisory, riderSpeedKph: 22, estimatedPassSpeedKph: nil
        )]
        let scriptedResumableRide = RideSummaryUpdate(
            rideId: rideId, recordingState: .paused,
            durationSeconds: 300, distanceMeters: 1_500, averageSpeedMPS: 5, maxSpeedMPS: 9
        )
        let flushed = LockIsolated<[TrackPointDTO]>([])
        let createdRide = LockIsolated<(UUID, Date)?>(nil)
        let updatedSummary = LockIsolated<RideSummaryUpdate?>(nil)
        let finalizedRide = LockIsolated<(UUID, Date, RideSummaryUpdate, URL?)?>(nil)
        let appendedPassEvents = LockIsolated<[VehiclePassEventDTO]>([])
        let client = PersistenceClient.mock(
            trackPoints: [rideId: scripted],
            rideExportMetadata: [rideId: scriptedRideMetadata],
            vehiclePassEvents: [rideId: scriptedPassEvents],
            resumableRide: scriptedResumableRide,
            onFlush: { flushed.setValue($0) },
            onCreateRide: { createdRide.setValue(($0, $1)) },
            onUpdateRideSummary: { updatedSummary.setValue($0) },
            onFinalizeRide: { finalizedRide.setValue(($0, $1, $2, $3)) },
            onAppendVehiclePassEvents: { appendedPassEvents.setValue($0) }
        )

        #expect(try await client.fetchTrackPoints(rideId) == scripted)
        #expect(try await client.fetchTrackPoints(UUID()).isEmpty)
        #expect(try await client.fetchRide(rideId) == scriptedRideMetadata)
        #expect(try await client.fetchVehiclePassEvents(rideId) == scriptedPassEvents)
        #expect(try await client.fetchVehiclePassEvents(UUID()).isEmpty)
        #expect(try await client.fetchResumableRide() == scriptedResumableRide)

        try await client.flushTrackPoints(scripted)
        #expect(flushed.value == scripted)

        let startedAt = Date()
        try await client.createRide(rideId, startedAt)
        #expect(createdRide.value?.0 == rideId)
        #expect(createdRide.value?.1 == startedAt)

        let summary = RideSummaryUpdate(rideId: rideId, durationSeconds: 120, distanceMeters: 500, averageSpeedMPS: 4, maxSpeedMPS: 9)
        try await client.updateRideSummary(summary)
        #expect(updatedSummary.value == summary)

        let endedAt = Date()
        let gpxURL = URL(string: "file:///tmp/scripted.gpx")!
        try await client.finalizeRide(rideId, endedAt, summary, gpxURL)
        #expect(finalizedRide.value?.0 == rideId)
        #expect(finalizedRide.value?.1 == endedAt)
        #expect(finalizedRide.value?.2 == summary)
        #expect(finalizedRide.value?.3 == gpxURL)

        let passEvent = VehiclePassEventDTO(
            rideId: rideId, timestamp: Date(), latitude: 1, longitude: 2,
            alertLevelAtPass: .caution, riderSpeedKph: 25, estimatedPassSpeedKph: 55
        )
        try await client.appendVehiclePassEvents([passEvent])
        #expect(appendedPassEvents.value == [passEvent])
    }

    @Test("mock's fetchRide throws rideNotFound for an unscripted rideId, matching live")
    func mockFetchRideThrowsForUnscriptedRideId() async throws {
        let client = PersistenceClient.mock(rideExportMetadata: [UUID(): RideExportMetadata(title: "Other Ride", startedAt: Date())])
        await #expect(throws: PersistenceError.rideNotFound) {
            try await client.fetchRide(UUID())
        }
    }

    // MARK: - Ride

    @Test("createRide persists a Ride with the given id, startedAt, and .active state")
    func createRidePersists() async throws {
        let (client, swiftDataStack) = Self.makeLiveClient()
        let rideId = UUID()
        let startedAt = Date()

        try await client.createRide(rideId, startedAt)

        let ride = try Self.fetchRide(rideId, from: swiftDataStack)
        #expect(ride.id == rideId)
        #expect(ride.startedAt == startedAt)
        #expect(ride.recordingState == .active)
        #expect(ride.endedAt == nil)
    }

    @Test("updateRideSummary writes aggregate metrics onto the existing Ride")
    func updateRideSummaryWritesAggregates() async throws {
        let (client, swiftDataStack) = Self.makeLiveClient()
        let rideId = UUID()
        try await client.createRide(rideId, Date())

        let update = RideSummaryUpdate(
            rideId: rideId,
            recordingState: .paused,
            durationSeconds: 1800,
            distanceMeters: 12_000,
            averageSpeedMPS: 6.5,
            maxSpeedMPS: 14.2,
            averageHeartRateBPM: 142,
            maxHeartRateBPM: 178,
            averageCadenceRPM: 82,
            maxCadenceRPM: 110,
            vehiclePassCount: nil
        )
        try await client.updateRideSummary(update)

        let ride = try Self.fetchRide(rideId, from: swiftDataStack)
        #expect(ride.recordingState == .paused)
        #expect(ride.durationSeconds == update.durationSeconds)
        #expect(ride.distanceMeters == update.distanceMeters)
        #expect(ride.averageSpeedMPS == update.averageSpeedMPS)
        #expect(ride.maxSpeedMPS == update.maxSpeedMPS)
        #expect(ride.averageHeartRateBPM == update.averageHeartRateBPM)
        #expect(ride.maxHeartRateBPM == update.maxHeartRateBPM)
        #expect(ride.averageCadenceRPM == update.averageCadenceRPM)
        #expect(ride.maxCadenceRPM == update.maxCadenceRPM)
    }

    @Test("updateRideSummary preserves an existing vehiclePassCount when the incoming update is nil")
    func updateRideSummaryPreservesVehiclePassCountWhenNil() async throws {
        let (client, swiftDataStack) = Self.makeLiveClient()
        let rideId = UUID()
        try await client.createRide(rideId, Date())
        try await client.updateRideSummary(RideSummaryUpdate(
            rideId: rideId, durationSeconds: 60, distanceMeters: 200,
            averageSpeedMPS: 3, maxSpeedMPS: 5, vehiclePassCount: 4
        ))

        try await client.updateRideSummary(RideSummaryUpdate(
            rideId: rideId, durationSeconds: 90, distanceMeters: 300,
            averageSpeedMPS: 3.2, maxSpeedMPS: 5, vehiclePassCount: nil
        ))

        let ride = try Self.fetchRide(rideId, from: swiftDataStack)
        #expect(ride.vehiclePassCount == 4)
        #expect(ride.distanceMeters == 300)
    }

    @Test("updateRideSummary on an unknown rideId throws rideNotFound")
    func updateRideSummaryUnknownRideThrows() async throws {
        let (client, _) = Self.makeLiveClient()
        let update = RideSummaryUpdate(rideId: UUID(), durationSeconds: 0, distanceMeters: 0, averageSpeedMPS: 0, maxSpeedMPS: 0)
        await #expect(throws: PersistenceError.rideNotFound) {
            try await client.updateRideSummary(update)
        }
    }

    @Test("finalizeRide writes final aggregates, endedAt, recordingState .ended, and gpxFileURL in one call")
    func finalizeRideSetsEndedState() async throws {
        let (client, swiftDataStack) = Self.makeLiveClient()
        let rideId = UUID()
        try await client.createRide(rideId, Date())
        let update = RideSummaryUpdate(
            rideId: rideId, recordingState: .ended,
            durationSeconds: 900, distanceMeters: 5_000, averageSpeedMPS: 5, maxSpeedMPS: 10
        )

        let endedAt = Date()
        let gpxURL = URL(string: "file:///tmp/ride.gpx")!
        try await client.finalizeRide(rideId, endedAt, update, gpxURL)

        let ride = try Self.fetchRide(rideId, from: swiftDataStack)
        #expect(ride.endedAt == endedAt)
        #expect(ride.recordingState == .ended)
        #expect(ride.distanceMeters == update.distanceMeters)
        #expect(ride.gpxFileURL == gpxURL)
    }

    @Test("finalizeRide always sets recordingState .ended regardless of the summary's recordingState")
    func finalizeRideForcesEndedRegardlessOfSummary() async throws {
        let (client, swiftDataStack) = Self.makeLiveClient()
        let rideId = UUID()
        try await client.createRide(rideId, Date())
        // A caller passing a stale/mismatched recordingState (e.g. .active) still
        // ends up .ended — finalizeRide is the one place that owns this transition.
        let update = RideSummaryUpdate(
            rideId: rideId, recordingState: .active,
            durationSeconds: 900, distanceMeters: 5_000, averageSpeedMPS: 5, maxSpeedMPS: 10
        )

        try await client.finalizeRide(rideId, Date(), update, nil)

        let ride = try Self.fetchRide(rideId, from: swiftDataStack)
        #expect(ride.recordingState == .ended)
    }

    @Test("finalizeRide on an unknown rideId throws rideNotFound")
    func finalizeRideUnknownRideThrows() async throws {
        let (client, _) = Self.makeLiveClient()
        let update = RideSummaryUpdate(rideId: UUID(), durationSeconds: 0, distanceMeters: 0, averageSpeedMPS: 0, maxSpeedMPS: 0)
        await #expect(throws: PersistenceError.rideNotFound) {
            try await client.finalizeRide(UUID(), Date(), update, nil)
        }
    }

    // MARK: - Ride read path (#173, for GPXExporter)

    @Test("fetchRide returns the ride's title and startedAt")
    func fetchRideReturnsMetadata() async throws {
        let (client, swiftDataStack) = Self.makeLiveClient()
        let rideId = UUID()
        let startedAt = Date()
        try await client.createRide(rideId, startedAt)

        let context = ModelContext(swiftDataStack.container)
        var descriptor = FetchDescriptor<Ride>(predicate: #Predicate { $0.id == rideId })
        descriptor.fetchLimit = 1
        let ride = try #require(try context.fetch(descriptor).first)
        ride.title = "Morning Ride"
        try context.save()

        let metadata = try await client.fetchRide(rideId)
        #expect(metadata.title == "Morning Ride")
        #expect(metadata.startedAt == startedAt)
    }

    @Test("fetchRide on an unknown rideId throws rideNotFound")
    func fetchRideUnknownRideThrows() async throws {
        let (client, _) = Self.makeLiveClient()
        await #expect(throws: PersistenceError.rideNotFound) {
            try await client.fetchRide(UUID())
        }
    }

    // MARK: - Ride.RecordingState query behavior (#171 follow-up)

    // SwiftData's #Predicate macro compiles a comparison against a captured
    // RawRepresentable-enum value fine, but faults at runtime — confirmed live via
    // a device log archive ("Unsupported Predicate: Captured/constant values of
    // type 'RecordingState' are not supported") after AppView's Rides list silently
    // never showed a completed ride. This documents the failure so a future revert
    // to a #Predicate-based filter breaks a test instead of shipping silently broken.
    @Test("a #Predicate comparing recordingState against a captured enum value throws at fetch time")
    func recordingStatePredicateThrowsAtRuntime() async throws {
        let (client, swiftDataStack) = Self.makeLiveClient()
        try await client.createRide(UUID(), Date())

        let context = ModelContext(swiftDataStack.container)
        let ended = Ride.RecordingState.ended
        let descriptor = FetchDescriptor<Ride>(predicate: #Predicate<Ride> { $0.recordingState == ended })

        #expect(throws: (any Error).self) {
            try context.fetch(descriptor)
        }
    }

    @Test("filtering fetched Rides in Swift (AppView's approach) returns only .ended rides, newest first")
    func endedRidesFilteredInSwift() async throws {
        let (client, swiftDataStack) = Self.makeLiveClient()
        let base = Date()
        let activeId = UUID()
        let pausedId = UUID()
        let endedId = UUID()

        try await client.createRide(activeId, base)
        try await client.createRide(pausedId, base.addingTimeInterval(60))
        try await client.createRide(endedId, base.addingTimeInterval(120))

        let pauseUpdate = RideSummaryUpdate(
            rideId: pausedId, recordingState: .paused,
            durationSeconds: 30, distanceMeters: 100, averageSpeedMPS: 3, maxSpeedMPS: 4
        )
        try await client.updateRideSummary(pauseUpdate)
        let finishUpdate = RideSummaryUpdate(
            rideId: endedId, recordingState: .ended,
            durationSeconds: 60, distanceMeters: 200, averageSpeedMPS: 3, maxSpeedMPS: 5
        )
        try await client.finalizeRide(endedId, base.addingTimeInterval(180), finishUpdate, nil)

        let context = ModelContext(swiftDataStack.container)
        let descriptor = FetchDescriptor<Ride>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        let items = try context.fetch(descriptor).filter { $0.recordingState == .ended }

        #expect(items.map(\.id) == [endedId])
    }

    // MARK: - fetchResumableRide (#175)

    @Test("fetchResumableRide returns nil when no rides exist")
    func fetchResumableRideNilWhenEmpty() async throws {
        let (client, _) = Self.makeLiveClient()
        #expect(try await client.fetchResumableRide() == nil)
    }

    @Test("fetchResumableRide returns nil when the only ride is .ended")
    func fetchResumableRideNilWhenOnlyEndedRideExists() async throws {
        let (client, _) = Self.makeLiveClient()
        let rideId = UUID()
        try await client.createRide(rideId, Date())
        let finishUpdate = RideSummaryUpdate(
            rideId: rideId, recordingState: .ended,
            durationSeconds: 60, distanceMeters: 200, averageSpeedMPS: 3, maxSpeedMPS: 5
        )
        try await client.finalizeRide(rideId, Date(), finishUpdate, nil)

        #expect(try await client.fetchResumableRide() == nil)
    }

    @Test("fetchResumableRide returns the non-ended ride's snapshot, ignoring an ended one")
    func fetchResumableRideReturnsNonEndedRide() async throws {
        let (client, _) = Self.makeLiveClient()
        let base = Date()
        let endedId = UUID()
        let activeId = UUID()

        try await client.createRide(endedId, base)
        let finishUpdate = RideSummaryUpdate(
            rideId: endedId, recordingState: .ended,
            durationSeconds: 60, distanceMeters: 200, averageSpeedMPS: 3, maxSpeedMPS: 5
        )
        try await client.finalizeRide(endedId, base.addingTimeInterval(60), finishUpdate, nil)

        try await client.createRide(activeId, base.addingTimeInterval(120))
        let checkpoint = RideSummaryUpdate(
            rideId: activeId, recordingState: .paused,
            durationSeconds: 145, distanceMeters: 980,
            averageSpeedMPS: 5.5, maxSpeedMPS: 11,
            averageHeartRateBPM: 140, maxHeartRateBPM: 172,
            averageCadenceRPM: 78, maxCadenceRPM: 105,
            vehiclePassCount: 2
        )
        try await client.updateRideSummary(checkpoint)

        let resumable = try await client.fetchResumableRide()
        #expect(resumable == checkpoint)
    }

    // MARK: - VehiclePassEvent (#172)

    @Test("appendVehiclePassEvents persists a queryable VehiclePassEvent linked by rideId")
    func appendVehiclePassEventsPersists() async throws {
        let (client, swiftDataStack) = Self.makeLiveClient()
        let rideId = UUID()
        try await client.createRide(rideId, Date())

        let dto = VehiclePassEventDTO(
            rideId: rideId,
            timestamp: Date(timeIntervalSince1970: 1_000_000),
            latitude: 36.0726,
            longitude: -79.7920,
            alertLevelAtPass: .caution,
            riderSpeedKph: 28.4,
            estimatedPassSpeedKph: 62.1
        )
        try await client.appendVehiclePassEvents([dto])

        let context = ModelContext(swiftDataStack.container)
        let events = try context.fetch(FetchDescriptor<VehiclePassEvent>())
        #expect(events.count == 1)
        let event = try #require(events.first)
        #expect(event.rideId == rideId)
        #expect(event.timestamp == dto.timestamp)
        #expect(event.latitude == dto.latitude)
        #expect(event.longitude == dto.longitude)
        #expect(event.alertLevelAtPass == .caution)
        #expect(event.riderSpeedKph == 28.4)
        #expect(event.estimatedPassSpeedKph == 62.1)
    }

    @Test("appendVehiclePassEvents inserts every event in the batch with a single call")
    func appendVehiclePassEventsBatchInsertsAll() async throws {
        let (client, swiftDataStack) = Self.makeLiveClient()
        let rideId = UUID()
        try await client.createRide(rideId, Date())

        let dtos = (0..<3).map { offset in
            VehiclePassEventDTO(
                rideId: rideId, timestamp: Date(timeIntervalSince1970: TimeInterval(offset)),
                latitude: 1, longitude: 2, alertLevelAtPass: .advisory,
                riderSpeedKph: 20, estimatedPassSpeedKph: 40
            )
        }
        try await client.appendVehiclePassEvents(dtos)

        let context = ModelContext(swiftDataStack.container)
        let events = try context.fetch(FetchDescriptor<VehiclePassEvent>())
        #expect(events.count == 3)
        #expect(Set(events.map(\.timestamp)) == Set(dtos.map(\.timestamp)))
    }

    @Test("appendVehiclePassEvents with a nil estimatedPassSpeedKph round-trips as nil")
    func appendVehiclePassEventNilEstimatedSpeedRoundTrips() async throws {
        let (client, swiftDataStack) = Self.makeLiveClient()
        let rideId = UUID()
        try await client.createRide(rideId, Date())

        try await client.appendVehiclePassEvents([VehiclePassEventDTO(
            rideId: rideId, timestamp: Date(), latitude: 1, longitude: 2,
            alertLevelAtPass: .danger, riderSpeedKph: 30, estimatedPassSpeedKph: nil
        )])

        let context = ModelContext(swiftDataStack.container)
        let events = try context.fetch(FetchDescriptor<VehiclePassEvent>())
        #expect(events.count == 1)
        #expect(events.first?.estimatedPassSpeedKph == nil)
    }

    @Test("appendVehiclePassEvents with an empty array is a no-op")
    func appendVehiclePassEventsEmptyArrayIsNoOp() async throws {
        let (client, swiftDataStack) = Self.makeLiveClient()
        try await client.appendVehiclePassEvents([])

        let context = ModelContext(swiftDataStack.container)
        let events = try context.fetch(FetchDescriptor<VehiclePassEvent>())
        #expect(events.isEmpty)
    }

    @Test("fetchVehiclePassEvents returns only the given ride's events, ascending by timestamp")
    func fetchVehiclePassEventsReturnsOwnEventsInOrder() async throws {
        let (client, _) = Self.makeLiveClient()
        let rideId = UUID()
        let otherRideId = UUID()
        let base = Date()

        let dtos = (0..<3).reversed().map { offset in
            VehiclePassEventDTO(
                rideId: rideId, timestamp: base.addingTimeInterval(TimeInterval(offset)),
                latitude: 1, longitude: 2, alertLevelAtPass: .caution,
                riderSpeedKph: 25, estimatedPassSpeedKph: 50
            )
        }
        let otherRideDto = VehiclePassEventDTO(
            rideId: otherRideId, timestamp: base, latitude: 0, longitude: 0,
            alertLevelAtPass: .danger, riderSpeedKph: 30, estimatedPassSpeedKph: nil
        )
        try await client.appendVehiclePassEvents(dtos + [otherRideDto])

        let fetched = try await client.fetchVehiclePassEvents(rideId)
        #expect(fetched.map(\.rideId) == Array(repeating: rideId, count: 3))
        #expect(fetched.map(\.timestamp) == dtos.map(\.timestamp).sorted())
    }

    @Test("fetchVehiclePassEvents for an unknown rideId returns empty, not an error")
    func fetchVehiclePassEventsUnknownRideIdIsEmpty() async throws {
        let (client, _) = Self.makeLiveClient()
        let fetched = try await client.fetchVehiclePassEvents(UUID())
        #expect(fetched.isEmpty)
    }

    private static func fetchRide(_ id: UUID, from swiftDataStack: SwiftDataStack) throws -> Ride {
        let context = ModelContext(swiftDataStack.container)
        var descriptor = FetchDescriptor<Ride>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        let ride = try context.fetch(descriptor).first
        return try #require(ride)
    }
}
