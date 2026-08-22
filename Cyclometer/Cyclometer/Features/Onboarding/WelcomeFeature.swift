import ComposableArchitecture

/// S01 — Welcome and permissions. Scaffold for #105; the real permission rows and
/// Next-button gating land with #106 in this same file.
@Reducer
struct WelcomeFeature {

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
