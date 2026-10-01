import SwiftUI
import ComposableArchitecture

/// W11 Pace on the dashboard.
struct PaceDashboardWidget: DashboardWidget {
    static let id = "pace"
    static let supportedSizes: [WidgetSize] = [.oneByOne]

    let size: WidgetSize
    let store: StoreOf<ActiveRideFeature>

    var body: some View {
        PaceWidget(speedMPS: store.speed.speedMPS ?? 0, unit: store.unitSystem)
    }
}
