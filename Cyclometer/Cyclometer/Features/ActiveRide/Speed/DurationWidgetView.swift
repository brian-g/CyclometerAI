import SwiftUI

// MARK: - W3 Duration Widget

/// W3 — Duration 1×1: moving time, leaving out stopped and paused seconds (#140).
struct DurationWidget: View {
    let movingSeconds: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel("Duration")
            HeroNumber(movingSeconds.formattedElapsed, unit: "").heroNumberSize(.medium)
            Spacer()
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.cyBgSecondary)
        .widgetDetail(label: DurationDashboardWidget.title, value: accessibilityValue) {
            RideMetricsSheet()
        }
    }

    /// What VoiceOver reads after the title (#361).
    var accessibilityValue: String { movingSeconds.spokenElapsed }
}

// MARK: - Previews

#Preview("Under an hour") {
    DurationWidget(movingSeconds: 2340)
        .frame(width: 196, height: 96)
}

#Preview("Over an hour — Dark") {
    DurationWidget(movingSeconds: 30_873)
        .frame(width: 196, height: 96)
        .preferredColorScheme(.dark)
}
