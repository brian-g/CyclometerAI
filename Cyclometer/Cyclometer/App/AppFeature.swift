import ComposableArchitecture

/// Root reducer — owns the three-page paged navigation state.
/// Pages: Ride Metrics (1) · Map/Navigation (2) · Radar Detail (3)
@Reducer
struct AppFeature {

    @ObservableState
    struct State: Equatable {
        var rideMetrics    = RideMetricsFeature.State()
        var mapNavigation  = MapNavigationFeature.State()
        var radarDetail    = RadarDetailFeature.State()
        var selectedPage   = Page.rideMetrics
        // Radar state is owned here so RideMetricsFeature can subscribe to it.
        // The radar column is only rendered on the Ride Metrics page.
        var radarTargets: [RadarTarget] = []
        var isRadarPaired: Bool = false
    }

    enum Page: Int, CaseIterable, Equatable {
        case rideMetrics   = 0
        case mapNavigation = 1
        case radarDetail   = 2
    }

    enum Action {
        case rideMetrics(RideMetricsFeature.Action)
        case mapNavigation(MapNavigationFeature.Action)
        case radarDetail(RadarDetailFeature.Action)
        case pageSelected(Page)
        case radarTargetsUpdated([RadarTarget])
        case radarPairingChanged(Bool)
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.rideMetrics,   action: \.rideMetrics)   { RideMetricsFeature() }
        Scope(state: \.mapNavigation, action: \.mapNavigation)  { MapNavigationFeature() }
        Scope(state: \.radarDetail,   action: \.radarDetail)    { RadarDetailFeature() }

        Reduce { state, action in
            switch action {
            case .pageSelected(let page):
                state.selectedPage = page
                return .none
            case .radarTargetsUpdated(let targets):
                state.radarTargets = targets
                return .none
            case .radarPairingChanged(let paired):
                state.isRadarPaired = paired
                return .none
            default:
                return .none
            }
        }
    }
}
