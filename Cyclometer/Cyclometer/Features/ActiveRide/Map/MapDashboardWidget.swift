import SwiftUI
import ComposableArchitecture

/// W8 Map on the dashboard: the track, the route being ridden (#199), and the sheet's saved
/// orientation with the action that switches it.
struct MapDashboardWidget: DashboardWidget {
    static let id = "map"
    static let supportedSizes: [WidgetSize] = [.twoByTwo]

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
    /// The route `LiveMapSheet` draws. W8 and W9 open the same sheet (#199, #200), so both read
    /// it here rather than each working it out.
    var mapSheetRoute: [RouteCoordinate] {
        navigation.activeRoute?.coordinates ?? []
    }
}
