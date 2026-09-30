import ComposableArchitecture
import Foundation

/// Buffers one `TrackPointDTO` per elapsed second (fed by `ActiveRideFeature.elapsedTick`)
/// into `RideDataBuffer` and flushes it to CoreData every 30s and again at ride end (#170).
@Reducer
struct TrackPointRecorderFeature {
    @ObservableState
    struct State: Equatable {
        var isRecording: Bool = false
    }

    enum Action: Equatable {
        case startRecording
        case pauseRecording
        case resumeRecording
        case timerTick(TrackPointDTO)
        case checkpointFired
        case stopRecording
    }

    @Dependency(\.rideDataBuffer) var rideDataBuffer
    @Dependency(\.persistenceClient) var persistenceClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .startRecording:
                state.isRecording = true
                return .none

            case .pauseRecording:
                state.isRecording = false
                return .none

            case .resumeRecording:
                state.isRecording = true
                return .none

            case .timerTick(let point):
                guard state.isRecording else { return .none }
                return .run { [rideDataBuffer] _ in
                    await rideDataBuffer.append(point)
                }

            case .checkpointFired:
                return flushEffect()

            case .stopRecording:
                state.isRecording = false
                return flushEffect()
            }
        }
    }

    /// No `.cancellable` here, unlike the SwiftData Ride-summary checkpoint's
    /// `.cancellable(id: .rideCheckpoint, cancelInFlight: true)`. `drainForFlush()` is
    /// destructive and actor-serialized: whichever call — the periodic `checkpointFired`
    /// or the final `stopRecording` — reaches the actor first drains whatever's currently
    /// buffered, and the other gets the (possibly empty) remainder. No point is ever lost
    /// or double-flushed, and `flushTrackPoints` is an append-only batch insert, not an
    /// overwrite, so ordering between the two doesn't matter — unlike `updateRideSummary`,
    /// which overwrites aggregate fields non-destructively and genuinely needs cancellation
    /// to stop a stale write from landing after the final one.
    private func flushEffect() -> Effect<Action> {
        .run { [rideDataBuffer, persistenceClient] _ in
            let points = await rideDataBuffer.drainForFlush()
            guard !points.isEmpty else { return }
            try? await persistenceClient.flushTrackPoints(points)
        }
    }
}
