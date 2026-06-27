import ComposableArchitecture
import Foundation

enum SensorSource: Equatable, Sendable {
    case none
    case gps
    case bleWheel
}

@Reducer
struct SpeedFeature {
    /// Rolling window of recent speed samples (m/s) feeding the widget's
    /// watermark sparkline. Bounded by sample count, not wall-clock time —
    /// CoreLocation does not emit at a fixed rate, so the window covers a
    /// variable real-time span.
    static let speedHistoryCapacity = 60

    @ObservableState
    struct State: Equatable {
        var speedMPS: Double? = nil
        var activeSpeedSource: SensorSource = .none
        var connectionState: BLECSCClient.ConnectionState = .disconnected
        var pairedPeripheralId: UUID? = nil
        var speedHistory: [Double] = []
    }

    enum Action: Equatable {
        case startListening
        case gpsSpeedReceived(Double)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .startListening:
                guard state.pairedPeripheralId != nil else { return .none }
                return .none

            case .gpsSpeedReceived(let speed):
                guard speed >= 0 else {
                    state.speedMPS = nil
                    state.activeSpeedSource = .none
                    return .none
                }
                state.speedMPS = speed
                state.activeSpeedSource = .gps
                state.speedHistory.append(speed)
                if state.speedHistory.count > Self.speedHistoryCapacity {
                    state.speedHistory.removeFirst()
                }
                return .none
            }
        }
    }
}
