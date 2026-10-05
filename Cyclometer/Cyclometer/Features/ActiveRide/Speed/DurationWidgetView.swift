import SwiftUI

// MARK: - W3 Duration Widget

/// W3 — Duration 1×1. The same ride time as W1's Time, which leaves out paused time (#140).
struct DurationWidget: View {
    let elapsed: Int   // seconds

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel("Duration")
            HeroNumber(elapsed.formattedElapsed, unit: "").heroNumberSize(.medium)
            Spacer()
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.cyBgSecondary)
        .widgetDetail(label: DurationDashboardWidget.title, value: accessibilityValue) {
            RideMetricsSheet()
        }
    }

    /// Spelled out: VoiceOver reads "1:02:33" digit by digit (#361).
    var accessibilityValue: String {
        Duration.seconds(elapsed).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }
}

// MARK: - Previews

#Preview("Under an hour") {
    DurationWidget(elapsed: 2340)
        .frame(width: 196, height: 96)
}

#Preview("Over an hour — Dark") {
    DurationWidget(elapsed: 30_873)
        .frame(width: 196, height: 96)
        .preferredColorScheme(.dark)
}
