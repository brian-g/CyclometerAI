import ComposableArchitecture
import Foundation

enum SensorSource: Equatable, Sendable {
    case none
    case gps
    case bleWheel
}

@Reducer
struct SpeedFeature {
    @ObservableState
    struct State: Equatable {
        var speedMPS: Double? = nil
        var activeSpeedSource: SensorSource = .none
        var connectionState: BLECSCClient.ConnectionState = .disconnected
        var pairedPeripheralId: UUID? = nil
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
                return .none
            }
        }
    }
}
