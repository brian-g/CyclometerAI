import Testing
import Foundation
import ComposableArchitecture
@testable import Cyclometer

@MainActor
@Suite("TrackPointRecorderFeature")
struct TrackPointRecorderFeatureTests {

    private static func point(_ n: Int) -> TrackPointDTO {
        TrackPointDTO(
            rideId: UUID(),
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

    private func makeStore(
        initialState: TrackPointRecorderFeature.State = TrackPointRecorderFeature.State(),
        persistenceClient: PersistenceClient = .testValue
    ) -> TestStoreOf<TrackPointRecorderFeature> {
        TestStore(initialState: initialState) {
            TrackPointRecorderFeature()
        } withDependencies: {
            $0.rideDataBuffer = RideDataBuffer()
            $0.persistenceClient = persistenceClient
        }
    }

    @Test("timerTick while recording buffers the point, flushed on the next checkpoint")
    func timerTickWhileRecordingBuffers() async {
        let flushed = LockIsolated<[TrackPointDTO]>([])
        let store = makeStore(
            initialState: TrackPointRecorderFeature.State(isRecording: true),
            persistenceClient: .mock(onFlush: { flushed.setValue($0) })
        )

        await store.send(.timerTick(Self.point(1)))
        await store.send(.checkpointFired)

        #expect(flushed.value.map(\.speedMPS) == [1])
    }

    @Test("timerTick while not recording is a no-op — nothing to flush at the next checkpoint")
    func timerTickWhileNotRecordingIsNoOp() async {
        let flushed = LockIsolated<[TrackPointDTO]>([])
        let store = makeStore(
            initialState: TrackPointRecorderFeature.State(isRecording: false),
            persistenceClient: .mock(onFlush: { flushed.setValue($0) })
        )

        await store.send(.timerTick(Self.point(1)))
        await store.send(.checkpointFired)

        #expect(flushed.value.isEmpty)
    }

    @Test("pauseRecording gates further ticks; resumeRecording re-enables them")
    func pauseGatesResumeReenables() async {
        let flushed = LockIsolated<[TrackPointDTO]>([])
        let store = makeStore(
            initialState: TrackPointRecorderFeature.State(isRecording: true),
            persistenceClient: .mock(onFlush: { flushed.setValue($0) })
        )

        await store.send(.pauseRecording) {
            $0.isRecording = false
        }
        await store.send(.timerTick(Self.point(1)))
        await store.send(.checkpointFired)
        #expect(flushed.value.isEmpty)

        await store.send(.resumeRecording) {
            $0.isRecording = true
        }
        await store.send(.timerTick(Self.point(2)))
        await store.send(.checkpointFired)
        #expect(flushed.value.map(\.speedMPS) == [2])
    }

    @Test("checkpointFired flushes exactly the buffered points; a second, empty checkpoint does not flush again")
    func checkpointFlushesExactlyBufferedPoints() async {
        let flushCount = LockIsolated(0)
        let flushed = LockIsolated<[TrackPointDTO]>([])
        let store = makeStore(
            initialState: TrackPointRecorderFeature.State(isRecording: true),
            persistenceClient: .mock(onFlush: {
                flushCount.withValue { $0 += 1 }
                flushed.setValue($0)
            })
        )

        await store.send(.timerTick(Self.point(1)))
        await store.send(.timerTick(Self.point(2)))
        await store.send(.checkpointFired)
        #expect(flushed.value.map(\.speedMPS) == [1, 2])
        #expect(flushCount.value == 1)

        // Nothing buffered since the last drain — checkpointFired's guard skips
        // calling flushTrackPoints at all.
        await store.send(.checkpointFired)
        #expect(flushCount.value == 1)
    }

    @Test("checkpointFired on an empty buffer never calls flushTrackPoints")
    func checkpointOnEmptyBufferNeverFlushes() async {
        let flushCount = LockIsolated(0)
        let store = makeStore(
            persistenceClient: .mock(onFlush: { _ in flushCount.withValue { $0 += 1 } })
        )

        await store.send(.checkpointFired)
        #expect(flushCount.value == 0)
    }

    @Test("stopRecording performs a final flush of any remaining buffered points")
    func stopRecordingFinalFlush() async {
        let flushed = LockIsolated<[TrackPointDTO]>([])
        let store = makeStore(
            initialState: TrackPointRecorderFeature.State(isRecording: true),
            persistenceClient: .mock(onFlush: { flushed.setValue($0) })
        )

        await store.send(.timerTick(Self.point(1)))
        await store.send(.stopRecording) {
            $0.isRecording = false
        }

        #expect(flushed.value.map(\.speedMPS) == [1])
    }

    private struct WriteFailed: Error {}

    @Test("a checkpoint whose write fails keeps its points, and the next checkpoint writes them once, in order (#345)")
    func failedCheckpointRetriesOnTheNext() async {
        let attempts = LockIsolated(0)
        let written = LockIsolated<[TrackPointDTO]>([])
        var client = PersistenceClient.testValue
        client.flushTrackPoints = { batch in
            let attempt = attempts.withValue { $0 += 1; return $0 }
            if attempt == 1 { throw WriteFailed() }
            written.withValue { $0 += batch }
        }
        let store = makeStore(
            initialState: TrackPointRecorderFeature.State(isRecording: true),
            persistenceClient: client
        )

        await store.send(.timerTick(Self.point(1)))
        await store.send(.timerTick(Self.point(2)))
        // Each step's effects drained before the next, so the order is the test's, not the executor's.
        await store.finish()
        await store.send(.checkpointFired)
        await store.finish()
        #expect(written.value.isEmpty)

        await store.send(.timerTick(Self.point(3)))
        await store.finish()
        await store.send(.checkpointFired)
        await store.finish()
        #expect(written.value.map(\.speedMPS) == [1, 2, 3])
        #expect(attempts.value == 2)
    }
}
