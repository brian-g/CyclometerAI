import Foundation
import Testing
@testable import Cyclometer

@Suite("RideDataBuffer")
struct RideDataBufferTests {

    private static func point(_ n: Int, rideId: UUID = UUID()) -> TrackPointDTO {
        TrackPointDTO(
            rideId: rideId,
            timestamp: Date(timeIntervalSince1970: TimeInterval(n)),
            latitude: 43.0,
            longitude: -89.0,
            altitudeMeters: 280.0,
            horizontalAccuracyMeters: 5.0,
            speedMPS: Double(n),
            speedSource: .gps,
            heartRateBPM: nil,
            heartRateSource: .none,
            cadenceRPM: nil,
            powerWatts: nil
        )
    }

    @Test("Appended points accumulate in order")
    func appendAccumulatesInOrder() async {
        let buffer = RideDataBuffer()
        await buffer.append(Self.point(1))
        await buffer.append(Self.point(2))
        await buffer.append(Self.point(3))

        let drained = await buffer.drainForFlush()
        #expect(drained.map(\.speedMPS) == [1, 2, 3])
    }

    @Test("drainForFlush returns then clears — a second drain is empty")
    func drainReturnsThenClears() async {
        let buffer = RideDataBuffer()
        await buffer.append(Self.point(1))

        let first = await buffer.drainForFlush()
        #expect(first.count == 1)

        let second = await buffer.drainForFlush()
        #expect(second.isEmpty)
    }

    @Test("Appending beyond capacity evicts the oldest point")
    func appendBeyondCapacityEvictsOldest() async {
        let buffer = RideDataBuffer()
        for n in 1...1_801 {
            await buffer.append(Self.point(n))
        }

        let drained = await buffer.drainForFlush()
        #expect(drained.count == 1_800)
        // Point 1 was evicted to make room for point 1,801 — the oldest surviving
        // point is 2.
        #expect(drained.first?.speedMPS == 2)
        #expect(drained.last?.speedMPS == 1_801)
    }

    @Test("totalPointCount tracks flushed plus pending across append/drain/append")
    func totalPointCountTracksFlushedPlusPending() async {
        let buffer = RideDataBuffer()
        await buffer.append(Self.point(1))
        await buffer.append(Self.point(2))
        #expect(await buffer.totalPointCount == 2)

        _ = await buffer.drainForFlush()
        #expect(await buffer.totalPointCount == 2)

        await buffer.append(Self.point(3))
        #expect(await buffer.totalPointCount == 3)
    }

    @Test("Concurrent appends are all retained — actor isolation serializes them")
    func concurrentAppendsAreSerialized() async {
        let buffer = RideDataBuffer()
        let rideId = UUID()
        await withTaskGroup(of: Void.self) { group in
            for n in 1...200 {
                group.addTask { await buffer.append(Self.point(n, rideId: rideId)) }
            }
        }
        #expect(await buffer.totalPointCount == 200)
        let drained = await buffer.drainForFlush()
        #expect(drained.count == 200)
    }
}
