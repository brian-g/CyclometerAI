import SwiftUI
import ComposableArchitecture

/// W1 Speed on the dashboard.
struct SpeedDashboardWidget: DashboardWidget {
    static let id = "speed"
    static let title = "Speed"
    static let supportedSizes: [WidgetSize] = [.oneByOne, .twoByOne, .twoByTwo]
    static let category = WidgetCategory.ride

    let size: WidgetSize
    let store: StoreOf<ActiveRideFeature>

    var body: some View {
        SpeedWidget(
            speed: store.speed.speedMPS,
            speedHistory: store.speed.watermarkSamples,
            activeSpeedSource: store.speed.activeSpeedSource,
            distance: store.distanceMeters,
            elapsed: store.elapsedSeconds,
            averageSpeed: store.averageSpeedMPS,
            maxSpeed: store.maxSpeedMPS,
            unit: store.unitSystem,
            size: size,
            metrics: { store.rideMetrics }
        )
    }
}
