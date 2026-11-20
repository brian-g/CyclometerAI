import ComposableArchitecture

/// S02 — Add Sensors (#107). The device list is S11's `DeviceManagementFeature`,
/// embedded rather than copied — role selection, replace-or-cancel, and pairing
/// persistence all come from there unchanged. This feature only adds the Next button
/// that advances onboarding.
@Reducer
struct SensorPairingFeature {
    @Dependency(\.bleCSCClient) var bleCSCClient

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
                //
                // A pairing still in flight is released the way the prompt's Cancel would
                // release it: nothing outlives this screen to receive its capabilities. The
                // `.onDisappear` above normally drops the slot too, as the last pairing scan
                // with no ride (#585); this covers a scan still held elsewhere, where the slot
                // would sit connected holding no role and its later release could end a Pair
                // the rider starts in Settings (#593).
                let abandoned = state.deviceManagement.pendingPairing
                state.deviceManagement.pendingPairing = nil
                let release: Effect<Action> = abandoned.map { id in
                    .run { [bleCSCClient] _ in await bleCSCClient.unpair(id) }
                } ?? .none
                return .concatenate(
                    .send(.deviceManagement(.onDisappear)),
                    release,
                    .send(.delegate(.next))
                )

            case .deviceManagement, .delegate:
                return .none
            }
        }
    }
}
