import ComposableArchitecture
import SwiftData

@Reducer
struct RidesFeature {
    @ObservableState
    struct State: Equatable {
        var demoRides: [DemoRide] = DemoRide.sampleRides
    }

    enum Action {
        case deleteRide(RideSummary)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .deleteRide(let ride):
                if case .demo(let id) = ride.source {
                    state.demoRides.removeAll { $0.id == id }
                }
                return .none
            }
        }
    }
}
