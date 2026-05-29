import ComposableArchitecture
import SwiftData

@Reducer
struct RidesFeature {
    @ObservableState
    struct State: Equatable {
        var demoRides: [DemoRide] = DemoRide.sampleRides
    }

    enum Action {
        case deleteDemoRide(UUID)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .deleteDemoRide(let id):
                state.demoRides.removeAll { $0.id == id }
                return .none
            }
        }
    }
}
