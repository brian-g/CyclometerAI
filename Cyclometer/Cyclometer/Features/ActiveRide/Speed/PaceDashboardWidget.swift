import SwiftUI
import ComposableArchitecture

/// W11 Pace on the dashboard.
struct PaceDashboardWidget: DashboardWidget {
    static let id = "pace"
    static let title = "Pace"
    static let supportedSizes: [WidgetSize] = [.oneByOne]
    static let category = WidgetCategory.ride

    let size: WidgetSize
    let store: StoreOf<ActiveRideFeature>

    var body: some View {
        PaceWidget(speedMPS: store.speed.speedMPS ?? 0, unit: store.unitSystem, metrics: { store.rideMetrics })
    }
}
