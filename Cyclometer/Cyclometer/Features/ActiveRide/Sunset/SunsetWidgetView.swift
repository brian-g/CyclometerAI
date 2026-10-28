import SwiftUI

// MARK: - W21 Sunset Widget

/// W21 — Sunset 1×1 (#462): hours and minutes until today's sunset where the rider is, worked out by
/// `Sunset.countdown`. "1:12", and "0:08" under an hour. Tapping opens the map sheet, as W9 does.
///
/// Always on the dashboard: with no fix yet, no sunset today (polar day or night), or after sunset,
/// it reads "—".
struct SunsetWidget: View {
    let countdown: Sunset.Countdown
    /// The map sheet, W8's. A closure so the dashboard never reads the (growing) track itself —
    /// only the presented sheet does (#362).
    var detail: () -> LiveMapSheet = { .placeholder }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel("To Sunset")
            HeroNumber(value, unit: "").heroNumberSize(.medium)
            Spacer()
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.cyBgSecondary)
        .widgetDetail(label: SunsetDashboardWidget.title, value: accessibilityValue, detail)
    }

    private var value: String {
        guard case .minutesLeft(let minutes) = countdown else { return "—" }
        return Duration.seconds(minutes * 60).formatted(.time(pattern: .hourMinute(padHourToLength: 1)))
    }

    /// What VoiceOver reads after "Sunset" (#361): "in 1 hour, 12 minutes", or why there is no
    /// countdown.
    var accessibilityValue: String {
        switch countdown {
        case .minutesLeft(let minutes):
            "in " + Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide))
        case .passed: "After sunset"
        case .noSunset: "No sunset today"
        case .noFix: "No location"
        }
    }
}

// MARK: - Previews

#Preview("Countdown") {
    SunsetWidget(countdown: .minutesLeft(72))
        .frame(width: 196, height: 96)
}

#Preview("Under an Hour") {
    SunsetWidget(countdown: .minutesLeft(8))
        .frame(width: 196, height: 96)
}

#Preview("After Sunset") {
    SunsetWidget(countdown: .passed)
        .frame(width: 196, height: 96)
}

#Preview("No Sunset Today") {
    SunsetWidget(countdown: .noSunset)
        .frame(width: 196, height: 96)
}

#Preview("No Fix") {
    SunsetWidget(countdown: .noFix)
        .frame(width: 196, height: 96)
}

#Preview("Countdown — Dark") {
    SunsetWidget(countdown: .minutesLeft(72))
        .frame(width: 196, height: 96)
        .preferredColorScheme(.dark)
}

#Preview("No Fix — Dark") {
    SunsetWidget(countdown: .noFix)
        .frame(width: 196, height: 96)
        .preferredColorScheme(.dark)
}
