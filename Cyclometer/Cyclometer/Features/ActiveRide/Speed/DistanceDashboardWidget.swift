import SwiftUI
import ComposableArchitecture

/// W6 Distance on the dashboard.
struct DistanceDashboardWidget: DashboardWidget {
    static let id = "distance"
    static let title = "Distance"
    static let supportedSizes: [WidgetSize] = [.oneByOne]
    static let category = WidgetCategory.ride

    let size: WidgetSize
    let store: StoreOf<ActiveRideFeature>

    var body: some View {
        DistanceWidget(distance: store.distanceMeters, unit: store.unitSystem)
    }
}
