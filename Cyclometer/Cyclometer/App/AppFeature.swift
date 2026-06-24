import ComposableArchitecture
import SwiftData

/// Root feature — owns tab selection and active ride lifecycle.
/// Navigation follows Apple Music pattern: Rides / Routes / Settings tabs.
/// Active ride dashboard is a fullScreenCover over the tab structure.
@Reducer
struct AppFeature {

    @ObservableState
    struct State: Equatable {
        var selectedTab: Tab = .rides
        var activeRide: ActiveRideFeature.State? = nil
        var isShowingNewRide: Bool = false
        var isDashboardPresented: Bool = false
        var rides: RidesFeature.State = RidesFeature.State()
        var routes: RoutesFeature.State = RoutesFeature.State()
        var settings: SettingsFeature.State = SettingsFeature.State()
    }

    enum Tab: Hashable {
        case rides, routes, settings
    }

    enum Action {
        case tabSelected(Tab)
        case startRideTapped
        case newRideSheetDismissed
        case rideStartConfirmed
        case dashboardDismissed
        case dashboardOpened
        case rideFinished
        case rides(RidesFeature.Action)
        case routes(RoutesFeature.Action)
        case settings(SettingsFeature.Action)
        case activeRide(ActiveRideFeature.Action)
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.rides,    action: \.rides)    { RidesFeature() }
        Scope(state: \.routes,   action: \.routes)   { RoutesFeature() }
        Scope(state: \.settings, action: \.settings) { SettingsFeature() }

        Reduce { state, action in
            switch action {
            case .tabSelected(let tab):
                state.selectedTab = tab
                return .none

            case .startRideTapped:
                state.isShowingNewRide = true
                return .none

            case .newRideSheetDismissed:
                state.isShowingNewRide = false
                return .none

            case .rideStartConfirmed:
                state.activeRide = ActiveRideFeature.State()
                state.isShowingNewRide = false
                state.isDashboardPresented = true
                state.selectedTab = .rides
                return .none

            case .dashboardDismissed:
                state.isDashboardPresented = false
                return .none

            case .dashboardOpened:
                if state.activeRide != nil { state.isDashboardPresented = true }
                return .none

            case .rideFinished:
                // TODO: persist ride summary to SwiftData before clearing state (M7).
                state.activeRide = nil
                state.isDashboardPresented = false
                return .none

            case .activeRide(.finishAlert(.presented(.confirmFinish))):
                state.activeRide = nil
                state.isDashboardPresented = false
                return .none

            case .rides, .routes, .settings, .activeRide:
                return .none
            }
        }
        .ifLet(\.activeRide, action: \.activeRide) {
            ActiveRideFeature()
        }
    }
}
