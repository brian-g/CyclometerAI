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
                // End the device list's pairing scan here, while this state still exists. Next
                // completes onboarding, and `AppFeature` nils `onboarding` straight away, so the
                // list's own `.onDisappear` arrives at an absent child and `ifLet` drops it. That
                // left every client's scan count at 1 for the first session, so no later release
                // reached 0 and #585's drop never ran.
                return .concatenate(
                    .send(.deviceManagement(.onDisappear)),
                    .send(.delegate(.next))
                )

            case .deviceManagement, .delegate:
                return .none
            }
        }
    }
}
