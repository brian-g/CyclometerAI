import ComposableArchitecture

/// S02 — Add Sensors (#107). The device list is S11's `DeviceManagementFeature`,
/// embedded rather than copied — role selection, replace-or-cancel, and pairing
/// persistence all come from there unchanged. This feature only adds the Next button
/// that advances onboarding.
@Reducer
struct SensorPairingFeature {

    @ObservableState
    struct State: Equatable {
        var deviceManagement = DeviceManagementFeature.State()
    }

    enum Action: Equatable {
        case nextButtonTapped
        case deviceManagement(DeviceManagementFeature.Action)
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case next
        }
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.deviceManagement, action: \.deviceManagement) {
            DeviceManagementFeature()
        }
        Reduce { state, action in
            switch action {
            case .nextButtonTapped:
                return .send(.delegate(.next))

            case .deviceManagement, .delegate:
                return .none
            }
        }
    }
}
