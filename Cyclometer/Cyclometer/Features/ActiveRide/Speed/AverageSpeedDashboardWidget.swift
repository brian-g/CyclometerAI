import SwiftUI
import ComposableArchitecture

/// W2 Average Speed on the dashboard.
struct AverageSpeedDashboardWidget: DashboardWidget {
    static let id = "averageSpeed"
    static let title = "Average Speed"
    static let supportedSizes: [WidgetSize] = [.oneByOne]
    static let category = WidgetCategory.ride

    let size: WidgetSize
    let store: StoreOf<ActiveRideFeature>

    var body: some View {
        AverageSpeedWidget(
            averageSpeed: store.averageSpeedMPS,
            speedHistory: store.speed.speedSamples.bucketAveraged(to: SpeedFeature.watermarkResolution),
            averageHistory: store.averageSpeedSamples.bucketAveraged(to: SpeedFeature.watermarkResolution),
            unit: store.unitSystem
        )
    }
}
