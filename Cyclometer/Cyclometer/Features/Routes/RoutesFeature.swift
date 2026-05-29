import ComposableArchitecture

@Reducer
struct RoutesFeature {
    @ObservableState
    struct State: Equatable {
        var showsMap: Bool = false
    }
    enum Action {
        case mapToggled
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .mapToggled:
                state.showsMap.toggle()
                return .none
            }
        }
    }
}
