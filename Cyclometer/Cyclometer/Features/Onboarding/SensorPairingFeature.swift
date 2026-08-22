import ComposableArchitecture

/// S02 — Add Sensors. Scaffold for #105; the real sensor list (shared with S11) lands
/// with #107 in this same file.
@Reducer
struct SensorPairingFeature {

    @ObservableState
    struct State: Equatable {}

    enum Action: Equatable {
        case nextButtonTapped
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case next
        }
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .nextButtonTapped:
                return .send(.delegate(.next))

            case .delegate:
                return .none
            }
        }
    }
}
