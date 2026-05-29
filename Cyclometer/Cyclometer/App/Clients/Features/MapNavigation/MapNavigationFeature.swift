import ComposableArchitecture
import CoreLocation

/// Page 2 — Live map with GPX route overlay and turn-by-turn cues.
/// Navigation: GPX import only (no MKDirections routing). tribos.studio integration planned.
@Reducer
struct MapNavigationFeature {

    @ObservableState
    struct State: Equatable {
        var currentLocation: CLLocationCoordinate2D?
        var isNavigating: Bool = false
        var gpxRouteLoaded: Bool = false
        var currentTurnInstruction: String = ""
        var distanceToNextTurnM: Double = 0
    }

    enum Action {
        case onAppear
        case locationUpdated(CLLocationCoordinate2D)
        case loadGPXRoute(URL)
        case gpxRouteLoadedSuccessfully
        case gpxRouteLoadFailed(String)
        case startNavigation
        case stopNavigation
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .none
            case .locationUpdated(let coord):
                state.currentLocation = coord
                return .none
            case .loadGPXRoute:
                // TODO: Parse GPX, build route
                return .none
            case .gpxRouteLoadedSuccessfully:
                state.gpxRouteLoaded = true
                return .none
            case .gpxRouteLoadFailed:
                state.gpxRouteLoaded = false
                return .none
            case .startNavigation:
                state.isNavigating = true
                return .none
            case .stopNavigation:
                state.isNavigating = false
                return .none
            }
        }
    }
}
