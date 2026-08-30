import ComposableArchitecture
import Foundation
import Testing
@testable import Cyclometer

@Suite("PersistenceClient")
struct PersistenceClientTests {

    /// Fresh in-memory CoreData stack per test — no shared state, no disk I/O.
    static func makeLiveClient() -> PersistenceClient {
        let stack = CoreDataStack(inMemory: true)
        return PersistenceClient.live(container: stack.container)
    }

    @Test("flushed points are queryable by rideId, ordered by timestamp")
    func flushAndFetchRoundTrip() async throws {
        let client = Self.makeLiveClient()
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
        let client = Self.makeLiveClient()
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
        let client = Self.makeLiveClient()
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
    }

    @Test("mock returns exactly what it is scripted with, and reports flushed points")
    func mockReturnsScriptedValues() async throws {
        let rideId = UUID()
        let scripted = [TrackPointDTO(rideId: rideId, timestamp: Date(), latitude: 1, longitude: 1, altitudeMeters: 0, horizontalAccuracyMeters: 0, speedSource: .gps, heartRateSource: .bleHR)]
        let flushed = LockIsolated<[TrackPointDTO]>([])
        let client = PersistenceClient.mock(
            trackPoints: [rideId: scripted],
            onFlush: { flushed.setValue($0) }
        )

        #expect(try await client.fetchTrackPoints(rideId) == scripted)
        #expect(try await client.fetchTrackPoints(UUID()).isEmpty)

        try await client.flushTrackPoints(scripted)
        #expect(flushed.value == scripted)
    }
}
