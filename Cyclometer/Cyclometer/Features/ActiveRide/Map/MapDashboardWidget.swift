import SwiftUI
import ComposableArchitecture

/// W8 Map on the dashboard: the track, the route being ridden (#199), and the sheet's saved
/// orientation with the action that switches it.
struct MapDashboardWidget: DashboardWidget {
    static let id = "map"
    static let title = "Map"
    static let supportedSizes: [WidgetSize] = [.twoByTwo]
    static let category = WidgetCategory.route

    let size: WidgetSize
    let store: StoreOf<ActiveRideFeature>

    var body: some View {
        MapWidget(
            trackSegments: store.trackSegments,
            route: store.mapSheetRoute,
            sheetOrientation: store.preferences.mapOrientation,
            onOrientationToggle: { store.send(.mapOrientationToggled) },
            size: size
        )
    }
}

extension ActiveRideFeature.State {
    /// The route `LiveMapSheet` draws. W8, W9, W19, W20 and W21 open the same sheet (#199, #200, #461, #462),
    /// so all read it here rather than each working it out.
    var mapSheetRoute: [RouteCoordinate] {
        navigation.activeRoute?.coordinates ?? []
    }
}

extension Store where State == ActiveRideFeature.State, Action == ActiveRideFeature.Action {
    /// The map sheet W9, W19, W20 and W21 open, built only when it presents, so a track point doesn't
    /// re-render the card that opens it (#362, #487). W8 builds its own from the track it already
    /// draws.
    var liveMapSheet: LiveMapSheet {
        LiveMapSheet(
            trackSegments: self.trackSegments,
            route: self.mapSheetRoute,
            orientation: self.preferences.mapOrientation,
            onOrientationToggle: { self.send(.mapOrientationToggled) }
        )
    }
}
