import SwiftUI

// MARK: - W11 Pace Widget

/// W11 — Pace 1×1
struct PaceWidget: View {
    let speedMPS: Double
    let unit: UnitSystem
    /// The Ride Metrics sheet's data. A closure so the card never reads it; only the open sheet does,
    /// in its own body (#144).
    var metrics: () -> RideMetrics = { RideMetrics() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel("Pace")
            HeroNumber(unit.formattedPace(fromMPS: speedMPS) ?? "--:--", unit: unit.paceLabel).heroNumberSize(.medium)
            Spacer()
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.cyBgSecondary)
        .widgetDetail(label: PaceDashboardWidget.title, value: accessibilityValue) {
            RideMetricsSheet(metrics: metrics)
        }
    }

    /// What VoiceOver reads after the title (#144), with no "--:--" read aloud.
    var accessibilityValue: String { unit.spokenPace(fromMPS: speedMPS) ?? "No reading" }
}
