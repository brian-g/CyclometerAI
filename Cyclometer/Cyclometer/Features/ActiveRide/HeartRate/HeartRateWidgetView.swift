import SwiftUI

// MARK: - W4 Heart Rate / W12 HR Zones

/// Shared empty state for W4/W12 when neither BLE nor HealthKit has a reading (#161).
private struct NoHRSourceLabel: View {
    var body: some View {
        Text("No HR Source")
            .font(.caption)
            .foregroundStyle(.cyTextTertiary)
    }
}

/// W4 — Heart Rate 1×1
struct HeartRateWidget: View {
    /// `ActiveRideFeature.State.displayHeartRateBPM`, not the raw reading — it resolves
    /// a brief strap silence to the held value rather than to `0` (#221). `0` here means
    /// "no reading", which a connected strap does report: `—` is the honest answer, and
    /// distinct from `source == .none`'s "nothing is paired at all".
    let bpm: Int
    let zone: Int
    let source: HRSource
    /// The Heart Rate sheet's data. A closure so the card never reads it; only the open sheet
    /// does, in its own body (#145).
    var metrics: () -> HeartRateMetrics = { HeartRateMetrics() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel("Heart Rate")
            if source == .none {
                NoHRSourceLabel()
            } else {
                HeroNumber(bpm > 0 ? "\(bpm)" : "—", unit: "bpm").heroNumberSize(.medium)
            }
            Spacer()
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hrZone(zone).opacity(0.12))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.hrZone(zone))
                .frame(width: Spacing.hrBorderWidth)
        }
        .widgetDetail(label: HeartRateDashboardWidget.title, value: accessibilityValue) {
            HeartRateSheet(metrics: metrics)
        }
    }

    /// What VoiceOver reads after "Heart Rate" (#361), with no "—" read aloud.
    var accessibilityValue: String {
        if source == .none { return "No HR source" }
        guard bpm > 0 else { return "No reading" }
        return "\(bpm) beats per minute, zone \(zone)"
    }
}

/// W12 — HR Zones 1×1
struct HRZonesWidget: View {
    let zone: Int
    let source: HRSource
    /// See `HeartRateWidget.metrics`.
    var metrics: () -> HeartRateMetrics = { HeartRateMetrics() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel("Zone")
            if source == .none {
                NoHRSourceLabel()
            } else {
                HeroNumber(zone == 0 ? "—" : "Z\(zone)", unit: "").heroNumberSize(.medium)
            }
            Spacer()
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hrZone(zone).opacity(0.12))
        .widgetDetail(label: HRZonesDashboardWidget.title, value: accessibilityValue) {
            HeartRateSheet(metrics: metrics)
        }
    }

    /// What VoiceOver reads after "HR Zones" (#361), with no "—" read aloud.
    var accessibilityValue: String {
        if source == .none { return "No HR source" }
        return zone == 0 ? "No reading" : "Zone \(zone)"
    }
}
