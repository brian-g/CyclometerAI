import ComposableArchitecture
import Foundation
import SwiftData
import Testing
@testable import Cyclometer

@Suite("PersistenceClient")
struct PersistenceClientTests {

    /// Fresh in-memory CoreData + SwiftData stacks per test — no shared state, no disk I/O.
    /// The SwiftData stack is returned alongside the client so Ride tests can fetch
    /// directly against it — there's no `fetchRide` on the client, by design (#171's
    /// scope is write-only).
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
        try await client.createRide(UUID(), Date())
        let update = RideSummaryUpdate(rideId: UUID(), durationSeconds: 0, distanceMeters: 0, averageSpeedMPS: 0, maxSpeedMPS: 0)
        try await client.updateRideSummary(update)
        try await client.finalizeRide(UUID(), Date(), update)
    }

    @Test("mock returns exactly what it is scripted with, and reports flushed points")
    func mockReturnsScriptedValues() async throws {
        let rideId = UUID()
        let scripted = [TrackPointDTO(rideId: rideId, timestamp: Date(), latitude: 1, longitude: 1, altitudeMeters: 0, horizontalAccuracyMeters: 0, speedSource: .gps, heartRateSource: .bleHR)]
        let flushed = LockIsolated<[TrackPointDTO]>([])
        let createdRide = LockIsolated<(UUID, Date)?>(nil)
        let updatedSummary = LockIsolated<RideSummaryUpdate?>(nil)
        let finalizedRide = LockIsolated<(UUID, Date, RideSummaryUpdate)?>(nil)
        let client = PersistenceClient.mock(
            trackPoints: [rideId: scripted],
            onFlush: { flushed.setValue($0) },
            onCreateRide: { createdRide.setValue(($0, $1)) },
            onUpdateRideSummary: { updatedSummary.setValue($0) },
            onFinalizeRide: { finalizedRide.setValue(($0, $1, $2)) }
        )

        #expect(try await client.fetchTrackPoints(rideId) == scripted)
        #expect(try await client.fetchTrackPoints(UUID()).isEmpty)

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
        try await client.finalizeRide(rideId, endedAt, summary)
        #expect(finalizedRide.value?.0 == rideId)
        #expect(finalizedRide.value?.1 == endedAt)
        #expect(finalizedRide.value?.2 == summary)
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

    @Test("finalizeRide writes final aggregates, endedAt, and recordingState .ended in one call")
    func finalizeRideSetsEndedState() async throws {
        let (client, swiftDataStack) = Self.makeLiveClient()
        let rideId = UUID()
        try await client.createRide(rideId, Date())
        let update = RideSummaryUpdate(
            rideId: rideId, recordingState: .ended,
            durationSeconds: 900, distanceMeters: 5_000, averageSpeedMPS: 5, maxSpeedMPS: 10
        )

        let endedAt = Date()
        try await client.finalizeRide(rideId, endedAt, update)

        let ride = try Self.fetchRide(rideId, from: swiftDataStack)
        #expect(ride.endedAt == endedAt)
        #expect(ride.recordingState == .ended)
        #expect(ride.distanceMeters == update.distanceMeters)
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

        try await client.finalizeRide(rideId, Date(), update)

        let ride = try Self.fetchRide(rideId, from: swiftDataStack)
        #expect(ride.recordingState == .ended)
    }

    @Test("finalizeRide on an unknown rideId throws rideNotFound")
    func finalizeRideUnknownRideThrows() async throws {
        let (client, _) = Self.makeLiveClient()
        let update = RideSummaryUpdate(rideId: UUID(), durationSeconds: 0, distanceMeters: 0, averageSpeedMPS: 0, maxSpeedMPS: 0)
        await #expect(throws: PersistenceError.rideNotFound) {
            try await client.finalizeRide(UUID(), Date(), update)
        }
    }

    private static func fetchRide(_ id: UUID, from swiftDataStack: SwiftDataStack) throws -> Ride {
        let context = ModelContext(swiftDataStack.container)
        var descriptor = FetchDescriptor<Ride>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        let ride = try context.fetch(descriptor).first
        return try #require(ride)
    }
}
