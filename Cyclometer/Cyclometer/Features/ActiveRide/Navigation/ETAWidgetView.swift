import SwiftUI

// MARK: - W20 ETA Widget

/// W20 — ETA 1×1 (#461): the clock time the rider will finish the route, worked out by
/// `ETADashboardWidget.arrival`. On a 12-hour clock the day period is the unit, lowercase like every
/// unit: "3:42 pm". On a 24-hour clock there is none: "15:42". Tapping opens the map sheet, as W9
/// does.
///
/// Always on the dashboard: with no route, turn-by-turn off, the moving average not yet settled, or
/// the route complete, it reads "—".
struct ETAWidget: View {
    let arrival: Date?
    /// What the "—" means to VoiceOver: no route, or one that isn't followed.
    var hasRoute = true
    var isTurnByTurnEnabled = true
    /// The map sheet, W8's. A closure so the dashboard never reads the (growing) track itself —
    /// only the presented sheet does (#362).
    var detail: () -> LiveMapSheet = { .placeholder }

    /// Follows the device's 12- or 24-hour setting, which iOS folds into the current locale.
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel("ETA")
            if let arrival {
                let face = Self.clockFace(arrival, locale: locale, timeZone: timeZone)
                HeroNumber(face.time, unit: face.dayPeriod).heroNumberSize(.medium)
            } else {
                HeroNumber("—", unit: "").heroNumberSize(.medium)
            }
            Spacer()
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetSymbol("alarm")
        .background(Color.cyBgSecondary)
        .widgetDetail(label: "Arrival", value: accessibilityValue, detail)
    }

    /// What VoiceOver reads after "Arrival" (#361).
    private var accessibilityValue: String {
        arrival.map { Self.spokenArrival($0, locale: locale, timeZone: timeZone) }
            ?? RouteProgressReading.empty(hasRoute: hasRoute, isTurnByTurnEnabled: isTurnByTurnEnabled)
    }

    /// The hero's digits, and the day period as its unit — empty on a 24-hour clock.
    ///
    /// The digits are the locale's own short time with its day period taken out, so each clock keeps
    /// its own hour digits and separator: "9:05" (US), "09:05" (UK), "9.05" (Finland).
    static func clockFace(_ date: Date, locale: Locale, timeZone: TimeZone) -> (time: String, dayPeriod: String) {
        let pattern = DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: locale) ?? "HH:mm"
        let (digits, isTwelveHour) = withoutDayPeriod(pattern)
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = digits
        let time = formatter.string(from: date)
        guard isTwelveHour else { return (time, "") }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        let symbol = calendar.component(.hour, from: date) < 12 ? calendar.amSymbol : calendar.pmSymbol
        return (time, symbol.lowercased(with: locale))
    }

    /// A time pattern with its day period ("a", "b", "B") and the space beside it removed, and
    /// whether its hour is a 12-hour one ("h", "K"). Quoted literals are text, not fields, and are
    /// left alone.
    private static func withoutDayPeriod(_ pattern: String) -> (pattern: String, isTwelveHour: Bool) {
        var stripped = ""
        var isQuoted = false
        var isTwelveHour = false
        for character in pattern {
            if character == "'" {
                isQuoted.toggle()
            } else if !isQuoted {
                if "abB".contains(character) { continue }
                if "hK".contains(character) { isTwelveHour = true }
            }
            stripped.append(character)
        }
        return (stripped.trimmingCharacters(in: .whitespaces), isTwelveHour)
    }

    /// An arrival as VoiceOver reads it: "3:42 PM".
    static func spokenArrival(_ date: Date, locale: Locale, timeZone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone))
    }
}

// MARK: - Previews

/// 3:42 pm today.
private let previewArrival = Calendar.current.date(bySettingHour: 15, minute: 42, second: 0, of: .now)!

private func hourCycle(_ cycle: Locale.HourCycle) -> Locale {
    var components = Locale.Components(locale: .current)
    components.hourCycle = cycle
    return Locale(components: components)
}

#Preview("12-Hour") {
    ETAWidget(arrival: previewArrival)
        .frame(width: 196, height: 96)
        .environment(\.locale, hourCycle(.oneToTwelve))
}

#Preview("24-Hour") {
    ETAWidget(arrival: previewArrival)
        .frame(width: 196, height: 96)
        .environment(\.locale, hourCycle(.zeroToTwentyThree))
}

#Preview("No Route") {
    ETAWidget(arrival: nil, hasRoute: false)
        .frame(width: 196, height: 96)
}

#Preview("12-Hour — Dark") {
    ETAWidget(arrival: previewArrival)
        .frame(width: 196, height: 96)
        .environment(\.locale, hourCycle(.oneToTwelve))
        .preferredColorScheme(.dark)
}
