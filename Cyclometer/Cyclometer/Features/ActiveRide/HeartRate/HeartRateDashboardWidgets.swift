import SwiftUI
import ComposableArchitecture

/// W4 Heart Rate on the dashboard.
struct HeartRateDashboardWidget: DashboardWidget {
    static let id = "heartRate"
    static let title = "Heart Rate"
    static let supportedSizes: [WidgetSize] = [.oneByOne, .twoByOne]
    static let category = WidgetCategory.heartRate

    let size: WidgetSize
    let store: StoreOf<ActiveRideFeature>

    var body: some View {
        HeartRateWidget(
            bpm: store.displayHeartRateBPM,
            zone: store.displayHRZone,
            source: store.hrSource,
            history: store.hrWatermarkSamples,
            zoneBounds: store.hrZoneBounds,
            trend: store.hrTrend,
            averageBPM: store.averageHeartRateBPM,
            maxBPM: store.maxHeartRateBPM,
            size: size,
            metrics: { store.heartRateMetrics }
        )
    }
}

/// W12 HR Zones on the dashboard.
struct HRZonesDashboardWidget: DashboardWidget {
    static let id = "hrZones"
    static let title = "HR Zones"
    static let supportedSizes: [WidgetSize] = [.oneByOne, .twoByOne]
    static let category = WidgetCategory.heartRate

    let size: WidgetSize
    let store: StoreOf<ActiveRideFeature>

    var body: some View {
        HRZonesWidget(
            zone: store.displayHRZone,
            source: store.hrSource,
            zoneSeconds: store.hrZoneSeconds,
            size: size,
            metrics: { store.heartRateMetrics }
        )
    }
}
