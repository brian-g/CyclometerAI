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
        let series = Self.plottedSeries(speed: store.speed.speedSamples, average: store.averageSpeedSamples)
        AverageSpeedWidget(
            averageSpeed: store.averageSpeedMPS,
            speedHistory: series.speed,
            averageHistory: series.average,
            unit: store.unitSystem,
            metrics: { store.rideMetrics }
        )
    }

    /// Both series over the watermark's window, downsampled. The speed samples are trimmed on every
    /// reading, paused or not, but the average only gains (and trims) on moving ticks — so after a
    /// long stop its oldest samples would stretch the shared time axis past the watermark (#140
    /// review). Trimming to the watermark's oldest reading keeps one window for both.
    static func plottedSeries(
        speed: [SpeedSample],
        average: [SpeedSample]
    ) -> (speed: [SpeedSample], average: [SpeedSample]) {
        let windowStart = speed.first?.time ?? .distantPast
        return (
            speed.bucketAveraged(to: SpeedFeature.watermarkResolution),
            average.filter { $0.time >= windowStart }.bucketAveraged(to: SpeedFeature.watermarkResolution)
        )
    }
}
