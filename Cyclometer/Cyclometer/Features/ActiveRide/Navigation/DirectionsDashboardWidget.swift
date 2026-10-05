import SwiftUI
import ComposableArchitecture

/// W9 Directions on the dashboard (#200). Its tap opens W8's map sheet, built from the same inputs
/// as `MapDashboardWidget`'s but only when it presents, so a track point doesn't re-render W9 (#362).
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
            detail: {
                LiveMapSheet(
                    trackSegments: store.trackSegments,
                    route: store.mapSheetRoute,
                    orientation: store.preferences.mapOrientation,
                    onOrientationToggle: { store.send(.mapOrientationToggled) }
                )
            }
        )
    }
}
