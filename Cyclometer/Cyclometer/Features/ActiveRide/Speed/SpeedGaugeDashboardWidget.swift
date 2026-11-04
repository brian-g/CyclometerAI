import SwiftUI
import ComposableArchitecture

/// W1 Speed, option B (#534): the speed on a gauge, a second entry beside W1 in S08's picker.
struct SpeedGaugeDashboardWidget: DashboardWidget {
    static let id = "speedGauge"
    static let title = "Speed Gauge"
    static let supportedSizes: [WidgetSize] = [.twoByTwo]
    static let category = WidgetCategory.ride

    let size: WidgetSize
    let store: StoreOf<ActiveRideFeature>

    var body: some View {
        // W2's series, since the gauge draws W2's chart behind it.
        let series = AverageSpeedDashboardWidget.plottedSeries(
            speed: store.speed.speedSamples, average: store.averageSpeedSamples
        )
        SpeedGaugeWidget(
            speed: store.speed.speedMPS,
            speedHistory: series.speed,
            averageHistory: series.average,
            distance: store.distanceMeters,
            elapsed: store.elapsedSeconds,
            averageSpeed: store.averageSpeedMPS,
            maxSpeed: store.maxSpeedMPS,
            unit: store.unitSystem,
            metrics: { store.rideMetrics }
        )
    }
}
