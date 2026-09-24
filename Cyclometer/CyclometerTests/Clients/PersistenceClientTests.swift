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

    @Test("a zero sensor reading round-trips as 0, not as nil")
    func zeroSensorReadingsRoundTripAsZero() async throws {
        let (client, _) = Self.makeLiveClient()
        let rideId = UUID()
        // The coasting/stopped rider: every sensor is connected and reporting, and every
        // one of them legitimately reads 0. Storing 0 as the "no reading" sentinel used
        // to erase these on the way back out, so the GPX dropped the elements entirely
        // and misreported an active sensor as absent (#211).
        let point = TrackPointDTO(
            rideId: rideId,
            timestamp: Date(),
            latitude: 1,
            longitude: 2,
            altitudeMeters: 3,
            horizontalAccuracyMeters: 4,
            speedMPS: 0,
            speedSource: .gps,
            heartRateBPM: 0,
            heartRateSource: .bleHR,
            cadenceRPM: 0,
            powerWatts: 0
        )

        try await client.flushTrackPoints([point])

        let fetched = try await client.fetchTrackPoints(rideId)
        #expect(fetched.count == 1)
        #expect(fetched[0].speedMPS == 0)
        #expect(fetched[0].heartRateBPM == 0)
        #expect(fetched[0].cadenceRPM == 0)
        #expect(fetched[0].powerWatts == 0)
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
        #expect(try await client.importRoute(ImportedRoute(coordinates: [], cuePoints: [])) == .empty)
        #expect(try await client.fetchRoutes().isEmpty)
        #expect(try await client.fetchRoute(UUID()) == nil)
        #expect(try await client.fetchRouteRides(UUID()).isEmpty)
        try await client.deleteRoute(UUID())
        try await client.createRide(UUID(), Date(), nil)
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
        let createdRide = LockIsolated<(UUID, Date, RouteReference?)?>(nil)
        let updatedSummary = LockIsolated<RideSummaryUpdate?>(nil)
        let finalizedRide = LockIsolated<(UUID, Date, RideSummaryUpdate, URL?)?>(nil)
        let appendedPassEvents = LockIsolated<[VehiclePassEventDTO]>([])
        let client = PersistenceClient.mock(
            trackPoints: [rideId: scripted],
            rideExportMetadata: [rideId: scriptedRideMetadata],
            vehiclePassEvents: [rideId: scriptedPassEvents],
            resumableRide: scriptedResumableRide,
            onFlush: { flushed.setValue($0) },
            onCreateRide: { createdRide.setValue(($0, $1, $2)) },
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
        let route = RouteReference(id: UUID(), name: "Sauratown Loop")
        try await client.createRide(rideId, startedAt, route)
        #expect(createdRide.value?.0 == rideId)
        #expect(createdRide.value?.1 == startedAt)
        #expect(createdRide.value?.2 == route)

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

        try await client.createRide(rideId, startedAt, nil)

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
        try await client.createRide(rideId, Date(), nil)

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
            vehiclePassCount: nil,
            isAutoPaused: true,
            zeroSpeedSeconds: 7,
            speedSampleCount: 900,
            hrSampleCount: 850,
            cadenceSampleCount: 700
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
        #expect(ride.isAutoPaused == true)
        #expect(ride.zeroSpeedSeconds == 7)
        #expect(ride.speedSampleCount == 900)
        #expect(ride.hrSampleCount == 850)
        #expect(ride.cadenceSampleCount == 700)
    }

    @Test("updateRideSummary preserves an existing vehiclePassCount when the incoming update is nil")
    func updateRideSummaryPreservesVehiclePassCountWhenNil() async throws {
        let (client, swiftDataStack) = Self.makeLiveClient()
        let rideId = UUID()
        try await client.createRide(rideId, Date(), nil)
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
        try await client.createRide(rideId, Date(), nil)
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
        try await client.createRide(rideId, Date(), nil)
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

    // MARK: - Map thumbnail (#177)

    @Test("saveRideMapThumbnail stores both appearances on the ride, each in its own field")
    func saveRideMapThumbnailRoundTrips() async throws {
        let (client, swiftDataStack) = Self.makeLiveClient()
        let rideId = UUID()
        try await client.createRide(rideId, Date(), nil)
        let light = Data("light".utf8)
        let dark = Data("dark".utf8)

        try await client.saveRideMapThumbnail(rideId, light, dark)

        let ride = try Self.fetchRide(rideId, from: swiftDataStack)
        #expect(ride.mapThumbnailLight == light)
        #expect(ride.mapThumbnailDark == dark)
    }

    @Test("saveRideMapThumbnail on an unknown rideId throws rideNotFound")
    func saveRideMapThumbnailUnknownRideThrows() async throws {
        let (client, _) = Self.makeLiveClient()
        await #expect(throws: PersistenceError.rideNotFound) {
            try await client.saveRideMapThumbnail(UUID(), Data(), Data())
        }
    }

    @Test("fetchRideIdsMissingMapThumbnail returns finished rides without a thumbnail, newest first")
    func ridesMissingMapThumbnail() async throws {
        let (client, _) = Self.makeLiveClient()
        let update = { (id: UUID) in
            RideSummaryUpdate(rideId: id, recordingState: .ended,
                              durationSeconds: 60, distanceMeters: 100, averageSpeedMPS: 2, maxSpeedMPS: 3)
        }
        let base = Date(timeIntervalSince1970: 1_000_000)
        let older = UUID(), newer = UUID(), captured = UUID(), inProgress = UUID()
        for (offset, id) in [older, newer, captured, inProgress].enumerated() {
            try await client.createRide(id, base.addingTimeInterval(TimeInterval(offset) * 3_600), nil)
        }
        for id in [older, newer, captured] {
            try await client.finalizeRide(id, base.addingTimeInterval(86_400), update(id), nil)
        }
        try await client.saveRideMapThumbnail(captured, Data([1]), Data([2]))

        // Not the captured one, and not the ride still being recorded.
        #expect(try await client.fetchRideIdsMissingMapThumbnail() == [newer, older])
    }

    // MARK: - Ride read path (#173, for GPXExporter)

    @Test("fetchRide returns the ride's title and startedAt")
    func fetchRideReturnsMetadata() async throws {
        let (client, swiftDataStack) = Self.makeLiveClient()
        let rideId = UUID()
        let startedAt = Date()
        try await client.createRide(rideId, startedAt, nil)

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

    // MARK: - Ride stats read path (#251, for S15)

    @Test("fetchRideStats returns the finalized aggregates, nil cadence and pass count kept nil")
    func fetchRideStatsReturnsAggregates() async throws {
        let (client, _) = Self.makeLiveClient()
        let withSensors = UUID()
        try await client.createRide(withSensors, Date(), nil)
        try await client.finalizeRide(withSensors, Date(), RideSummaryUpdate(
            rideId: withSensors, durationSeconds: 120, distanceMeters: 500, averageSpeedMPS: 4, maxSpeedMPS: 9,
            averageCadenceRPM: 0, maxCadenceRPM: 104, vehiclePassCount: 3
        ), nil)
        let withoutSensors = UUID()
        try await client.createRide(withoutSensors, Date(), nil)
        try await client.finalizeRide(withoutSensors, Date(), RideSummaryUpdate(
            rideId: withoutSensors, durationSeconds: 60, distanceMeters: 200, averageSpeedMPS: 3, maxSpeedMPS: 5
        ), nil)

        // A real 0 rpm average must survive as 0, not collapse into "no sensor".
        #expect(try await client.fetchRideStats(withSensors) == RideStats(
            averageSpeedMPS: 4, maxSpeedMPS: 9, averageCadenceRPM: 0, maxCadenceRPM: 104, vehiclePassCount: 3
        ))
        #expect(try await client.fetchRideStats(withoutSensors) == RideStats(averageSpeedMPS: 3, maxSpeedMPS: 5))
    }

    @Test("fetchRideStats on an unknown rideId throws rideNotFound, live and mock alike")
    func fetchRideStatsUnknownRideThrows() async throws {
        let (client, _) = Self.makeLiveClient()
        await #expect(throws: PersistenceError.rideNotFound) {
            try await client.fetchRideStats(UUID())
        }
        await #expect(throws: PersistenceError.rideNotFound) {
            try await PersistenceClient.mock().fetchRideStats(UUID())
        }
    }

    @Test("fetchRideStats carries the route the ride followed, nil for a free ride")
    func fetchRideStatsCarriesRouteName() async throws {
        let (client, _) = Self.makeLiveClient()
        let onRoute = UUID()
        try await client.createRide(onRoute, Date(), RouteReference(id: UUID(), name: "SW Fargo"))
        let free = UUID()
        try await client.createRide(free, Date(), nil)

        #expect(try await client.fetchRideStats(onRoute).routeName == "SW Fargo")
        #expect(try await client.fetchRideStats(free).routeName == nil)
    }

    // MARK: - Rename (#249, for S10)

    @Test("renameRide stores the title, and the Rides list reads it back")
    func renameRideStoresTitle() async throws {
        let (client, swiftDataStack) = Self.makeLiveClient()
        let id = UUID()
        try await client.createRide(id, Date(), nil)
        try await client.finalizeRide(id, Date(), RideSummaryUpdate(
            rideId: id, durationSeconds: 60, distanceMeters: 200, averageSpeedMPS: 3, maxSpeedMPS: 5
        ), nil)

        try await client.renameRide(id, "Morning Loop")

        #expect(try await client.fetchRides().map(\.title) == ["Morning Loop"])
        #expect(try Self.fetchRide(id, from: swiftDataStack).title == "Morning Loop")
    }

    @Test("renameRide on an unknown rideId throws rideNotFound")
    func renameRideUnknownRideThrows() async throws {
        let (client, _) = Self.makeLiveClient()
        await #expect(throws: PersistenceError.rideNotFound) {
            try await client.renameRide(UUID(), "Nowhere")
        }
    }

    // MARK: - Ride.RecordingState query behavior (#171 follow-up)

    // On iOS 26, SwiftData's #Predicate macro compiled a comparison against a captured
    // RawRepresentable-enum value fine but faulted at runtime ("Unsupported Predicate:
    // Captured/constant values of type 'RecordingState' are not supported"). That was
    // confirmed live via a device log archive after AppView's Rides list silently never
    // showed a completed ride. iOS 27 fixed it. On 2026-09-15 all three states threw on
    // 26.5, and 27.0 returned the right rows. The deployment target is now 27.0, so this
    // pins the fixed behaviour. AppView and RidePersistenceActor still work around the
    // old fault, and no longer need to.
    @Test("a #Predicate comparing recordingState against a captured enum value returns only the matching rides")
    func recordingStatePredicateFiltersOnCapturedEnum() async throws {
        let (client, swiftDataStack) = Self.makeLiveClient()
        let base = Date()
        let activeId = UUID()
        let endedId = UUID()
        try await client.createRide(activeId, base, nil)
        try await client.createRide(endedId, base.addingTimeInterval(60), nil)
        let finishUpdate = RideSummaryUpdate(
            rideId: endedId, recordingState: .ended,
            durationSeconds: 60, distanceMeters: 200, averageSpeedMPS: 3, maxSpeedMPS: 5
        )
        try await client.finalizeRide(endedId, base.addingTimeInterval(120), finishUpdate, nil)

        let context = ModelContext(swiftDataStack.container)
        let ended = Ride.RecordingState.ended
        let descriptor = FetchDescriptor<Ride>(predicate: #Predicate<Ride> { $0.recordingState == ended })

        #expect(try context.fetch(descriptor).map(\.id) == [endedId])
    }

    @Test("filtering fetched Rides in Swift (AppView's approach) returns only .ended rides, newest first")
    func endedRidesFilteredInSwift() async throws {
        let (client, swiftDataStack) = Self.makeLiveClient()
        let base = Date()
        let activeId = UUID()
        let pausedId = UUID()
        let endedId = UUID()

        try await client.createRide(activeId, base, nil)
        try await client.createRide(pausedId, base.addingTimeInterval(60), nil)
        try await client.createRide(endedId, base.addingTimeInterval(120), nil)

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

    @Test("fetchResumableRide carries back the route, and how far along it the ride had got (#197)")
    func fetchResumableRideCarriesTheRouteAndProgress() async throws {
        let (client, _) = Self.makeLiveClient()
        let rideId = UUID()
        let route = RouteReference(id: UUID(), name: "Lake Loop")
        try await client.createRide(rideId, Date(), route)
        // The checkpoint's own `route` is nil. Only `createRide` writes the route, so a checkpoint
        // without one cannot erase it.
        try await client.updateRideSummary(RideSummaryUpdate(
            rideId: rideId,
            durationSeconds: 60,
            distanceMeters: 500,
            averageSpeedMPS: 8,
            maxSpeedMPS: 10,
            routeProgressMeters: 1_234
        ))

        let resumable = try #require(try await client.fetchResumableRide())
        #expect(resumable.route == route)
        #expect(resumable.routeProgressMeters == 1_234)
    }

    @Test("a free ride resumes with no route and no progress")
    func fetchResumableRideOfAFreeRideHasNoRoute() async throws {
        let (client, _) = Self.makeLiveClient()
        try await client.createRide(UUID(), Date(), nil)

        let resumable = try #require(try await client.fetchResumableRide())
        #expect(resumable.route == nil)
        #expect(resumable.routeProgressMeters == nil)
    }

    @Test("fetchResumableRide returns nil when no rides exist")
    func fetchResumableRideNilWhenEmpty() async throws {
        let (client, _) = Self.makeLiveClient()
        #expect(try await client.fetchResumableRide() == nil)
    }

    @Test("fetchResumableRide returns nil when the only ride is .ended")
    func fetchResumableRideNilWhenOnlyEndedRideExists() async throws {
        let (client, _) = Self.makeLiveClient()
        let rideId = UUID()
        try await client.createRide(rideId, Date(), nil)
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

        try await client.createRide(endedId, base, nil)
        let finishUpdate = RideSummaryUpdate(
            rideId: endedId, recordingState: .ended,
            durationSeconds: 60, distanceMeters: 200, averageSpeedMPS: 3, maxSpeedMPS: 5
        )
        try await client.finalizeRide(endedId, base.addingTimeInterval(60), finishUpdate, nil)

        try await client.createRide(activeId, base.addingTimeInterval(120), nil)
        let checkpoint = RideSummaryUpdate(
            rideId: activeId, recordingState: .paused,
            durationSeconds: 145, distanceMeters: 980,
            averageSpeedMPS: 5.5, maxSpeedMPS: 11,
            averageHeartRateBPM: 140, maxHeartRateBPM: 172,
            averageCadenceRPM: 78, maxCadenceRPM: 105,
            vehiclePassCount: 2,
            isAutoPaused: true,
            zeroSpeedSeconds: 9,
            speedSampleCount: 120,
            hrSampleCount: 90,
            cadenceSampleCount: 60
        )
        try await client.updateRideSummary(checkpoint)

        let resumable = try await client.fetchResumableRide()
        #expect(resumable == checkpoint)
    }

    // MARK: - fetchRides (#247)

    @Test("fetchRides returns only finished rides, newest first")
    func fetchRidesReturnsOnlyEndedRidesNewestFirst() async throws {
        let (client, _) = Self.makeLiveClient()
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        let older = UUID()
        let newer = UUID()
        let stillRiding = UUID()

        for (id, startedAt) in [(older, base), (newer, base.addingTimeInterval(86_400)),
                                (stillRiding, base.addingTimeInterval(172_800))] {
            try await client.createRide(id, startedAt, nil)
        }
        for (id, endedAt) in [(older, base.addingTimeInterval(3_600)),
                              (newer, base.addingTimeInterval(90_000))] {
            let summary = RideSummaryUpdate(
                rideId: id, recordingState: .ended,
                durationSeconds: 3_600, distanceMeters: 42_000,
                averageSpeedMPS: 6, maxSpeedMPS: 12
            )
            try await client.finalizeRide(id, endedAt, summary, nil)
        }
        // stillRiding is left un-finalized, the canary for the endedAt-proxy filter.

        let rides = try await client.fetchRides()

        #expect(rides.map(\.id) == [newer, older])
        #expect(rides.first?.distanceMeters == 42_000)
        #expect(rides.first?.durationSeconds == 3_600)
    }

    @Test("fetchRides with no finished rides returns empty")
    func fetchRidesWithNoFinishedRidesReturnsEmpty() async throws {
        let (client, _) = Self.makeLiveClient()
        try await client.createRide(UUID(), Date(), nil)
        #expect(try await client.fetchRides().isEmpty)
    }

    /// S14's row reads its thumbnail per ride rather than with `fetchRides` (#248), so a
    /// list reload doesn't pull every image off disk.
    @Test("fetchRideMapThumbnail returns both stored appearances, nil for a ride without them or an unknown id")
    func fetchRideMapThumbnailRoundTrips() async throws {
        let (client, _) = PersistenceClientTests.makeLiveClient()
        let captured = UUID(), uncaptured = UUID()
        for id in [captured, uncaptured] {
            try await client.createRide(id, Date(), nil)
        }
        try await client.saveRideMapThumbnail(captured, Data("light".utf8), Data("dark".utf8))

        #expect(try await client.fetchRideMapThumbnail(captured)
                == RideMapThumbnailData(light: Data("light".utf8), dark: Data("dark".utf8)))
        #expect(try await client.fetchRideMapThumbnail(uncaptured) == nil)
        #expect(try await client.fetchRideMapThumbnail(UUID()) == nil)
    }

    // MARK: - VehiclePassEvent (#172)

    @Test("appendVehiclePassEvents persists a queryable VehiclePassEvent linked by rideId")
    func appendVehiclePassEventsPersists() async throws {
        let (client, swiftDataStack) = Self.makeLiveClient()
        let rideId = UUID()
        try await client.createRide(rideId, Date(), nil)

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
        try await client.createRide(rideId, Date(), nil)

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
        try await client.createRide(rideId, Date(), nil)

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
