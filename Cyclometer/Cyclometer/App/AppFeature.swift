import ComposableArchitecture
import SwiftData

/// Root feature — owns tab selection and active ride lifecycle.
/// Navigation follows Apple Music pattern: Rides / Routes / Settings tabs.
/// Active ride dashboard is a custom screen over the tab structure.
@Reducer
struct AppFeature {

    @ObservableState
    struct State: Equatable {
        var selectedTab: Tab = .rides
        var activeRide: ActiveRideFeature.State? = nil
        @Presents var startSheet: StartSheetFeature.State? = nil
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
        case startRideButtonTapped
        case startSheet(PresentationAction<StartSheetFeature.Action>)
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

            case .startRideButtonTapped:
                state.startSheet = StartSheetFeature.State()
                return .none

            case .startSheet(.presented(.delegate(.startRide))):
                state.activeRide = ActiveRideFeature.State()
                state.startSheet = nil
                state.isDashboardPresented = true
                state.selectedTab = .rides
                // Start the ride's long-running effects (1 Hz timer, HR, radar,
                // location) here so they live for the whole ride — bound to
                // `activeRide` via `.ifLet` and torn down only when the ride
                // ends. Previously this was driven by RideDashboardView's
                // `.task`, so minimizing the dashboard cancelled the timer.
                return .send(.activeRide(.task))

            case .startSheet:
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
        .ifLet(\.$startSheet, action: \.startSheet) {
            StartSheetFeature()
        }
    }
}
