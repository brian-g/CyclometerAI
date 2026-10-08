import SwiftUI

// MARK: - W6 Distance Widget

/// W6 — Distance 1×1. `distanceMeters` integrates the displayed speed, so it follows the
/// active source — the wheel sensor over GPS (#381). Zero is a real distance, so there is no
/// empty state.
struct DistanceWidget: View {
    let distance: Double   // meters
    let unit: UnitSystem
    /// The Ride Metrics sheet's data. A closure so the card never reads it; only the open sheet does (#144).
    var metrics: () -> RideMetrics = { RideMetrics() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel("Distance")
            HeroNumber(unit.distance(fromMeters: distance), unit: unit.distanceLabel).heroNumberSize(.medium)
            Spacer()
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.cyBgSecondary)
        .widgetDetail(label: DistanceDashboardWidget.title, value: unit.spokenDistance(fromMeters: distance)) {
            RideMetricsSheet(metrics: metrics())
        }
    }
}

// MARK: - Previews

#Preview("Metric") {
    DistanceWidget(distance: 12_300, unit: .metric)
        .frame(width: 196, height: 96)
}

#Preview("Imperial — Dark") {
    DistanceWidget(distance: 12_300, unit: .imperial)
        .frame(width: 196, height: 96)
        .preferredColorScheme(.dark)
}
