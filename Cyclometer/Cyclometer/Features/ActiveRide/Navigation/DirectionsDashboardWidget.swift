import SwiftUI
import ComposableArchitecture

/// W9 Directions on the dashboard (#200). Its tap opens W8's map sheet, so it carries the same
/// sheet inputs as `MapDashboardWidget`.
struct DirectionsDashboardWidget: DashboardWidget {
    static let id = "directions"
    static let title = "Directions"
    static let supportedSizes: [WidgetSize] = [.oneByOne, .twoByOne]
    static let category = WidgetCategory.route

    let size: WidgetSize
    let store: StoreOf<ActiveRideFeature>

    var body: some View {
        DirectionsWidget(
            hasRoute: store.navigation.activeRoute != nil,
            nextTurn: store.navigation.nextManeuver,
            distanceMeters: store.navigation.distanceToNextTurnMeters,
            unit: store.unitSystem,
            size: size,
            trackSegments: store.trackSegments,
            route: store.mapSheetRoute,
            sheetOrientation: store.preferences.mapOrientation,
            onOrientationToggle: { store.send(.mapOrientationToggled) }
        )
    }
}
