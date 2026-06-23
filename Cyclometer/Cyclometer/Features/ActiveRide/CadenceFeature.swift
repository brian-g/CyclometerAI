import ComposableArchitecture
import Foundation

@Reducer
struct CadenceFeature {
    @ObservableState
    struct State: Equatable {
        var cadenceRPM: Int? = nil
        var connectionState: BLECSCClient.ConnectionState = .disconnected
        var pairedPeripheralId: UUID? = nil
    }

    enum Action: Equatable {
        case startListening
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .startListening:
                guard state.pairedPeripheralId != nil else { return .none }
                return .none
            }
        }
    }
}
