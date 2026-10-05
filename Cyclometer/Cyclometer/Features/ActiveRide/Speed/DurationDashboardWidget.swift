import SwiftUI
import ComposableArchitecture

/// W3 Duration on the dashboard.
struct DurationDashboardWidget: DashboardWidget {
    static let id = "duration"
    static let title = "Duration"
    static let supportedSizes: [WidgetSize] = [.oneByOne]
    static let category = WidgetCategory.ride

    let size: WidgetSize
    let store: StoreOf<ActiveRideFeature>

    var body: some View {
        DurationWidget(elapsed: store.elapsedSeconds)
    }
}
