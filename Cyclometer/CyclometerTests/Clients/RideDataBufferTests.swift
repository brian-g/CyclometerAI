import ComposableArchitecture
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


    @Test("A failed flush puts its batch back ahead of newer points, and the next flush writes both in order (#345)")
    func failedFlushRequeuesInOrder() async throws {
        let buffer = RideDataBuffer()
        await buffer.append(Self.point(1))
        await buffer.append(Self.point(2))

        await #expect(throws: WriteFailed.self) {
            try await buffer.flush { _ in throw WriteFailed() }
        }
        await buffer.append(Self.point(3))

        let written = LockIsolated<[TrackPointDTO]>([])
        try await buffer.flush { batch in written.withValue { $0 += batch } }
        #expect(written.value.map(\.speedMPS) == [1, 2, 3])
        #expect(await buffer.totalPointCount == 3)
        #expect(await buffer.drainForFlush().isEmpty)
    }

    @Test("A flush waits for the one in flight, and writes the batch that one put back ahead of its own (#345)")
    func overlappingFlushesAreSerialized() async throws {
        let buffer = RideDataBuffer()
        await buffer.append(Self.point(1))
        await buffer.append(Self.point(2))

        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let (release, releaseContinuation) = AsyncStream<Void>.makeStream()
        let first = Task {
            try await buffer.flush { _ in
                startedContinuation.yield()
                for await _ in release { break }
                throw WriteFailed()
            }
        }
        for await _ in started { break }

        await buffer.append(Self.point(3))
        let written = LockIsolated<[[TrackPointDTO]]>([])
        let second = Task {
            try await buffer.flush { batch in written.withValue { $0.append(batch) } }
        }
        releaseContinuation.yield()

        await #expect(throws: WriteFailed.self) { try await first.value }
        try await second.value
        #expect(written.value.map { $0.map(\.speedMPS) } == [[1, 2, 3]])
    }

    @Test("Points evicted over capacity by a put-back batch are counted lost, as a span of time (#345)")
    func evictionIsLost() async throws {
        let buffer = RideDataBuffer()
        for n in 1...1_800 { await buffer.append(Self.point(n)) }
        await #expect(throws: WriteFailed.self) { try await buffer.flush { _ in throw WriteFailed() } }
        #expect(await buffer.takeLost() == nil)

        await buffer.append(Self.point(1_801))
        await buffer.append(Self.point(1_802))
        #expect(await buffer.takeLost() == Self.point(1).timestamp...Self.point(2).timestamp)
        #expect(await buffer.takeLost() == nil)
    }

    @Test("Discarded points are lost, not flushed (#345)")
    func discardIsLostNotFlushed() async {
        let buffer = RideDataBuffer()
        await buffer.append(Self.point(1))
        _ = await buffer.drainForFlush()
        await buffer.append(Self.point(2))
        await buffer.append(Self.point(3))

        await buffer.discardUnwritten()

        #expect(await buffer.totalPointCount == 1)
        #expect(await buffer.drainForFlush().isEmpty)
        #expect(await buffer.takeLost() == Self.point(2).timestamp...Self.point(3).timestamp)
    }
}
