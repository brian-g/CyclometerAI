import SwiftUI

// MARK: - W20 ETA Widget

/// W20 — ETA 1×1 (#461): the clock time the rider will finish the route, worked out by
/// `ETADashboardWidget.arrival`. On a 12-hour clock the day period is the unit, lowercase like every
/// unit: "3:42 pm". On a 24-hour clock there is none: "15:42". Tapping opens the map sheet, as W9
/// does.
///
/// Always on the dashboard: with no route, no moving average yet, or the route complete, it reads "—".
struct ETAWidget: View {
    let arrival: Date?
    /// The map sheet, W8's. A closure so the dashboard never reads the (growing) track itself —
    /// only the presented sheet does (#362).
    var detail: () -> LiveMapSheet = {
        LiveMapSheet(trackSegments: [[]], route: [], orientation: .headingUp, onOrientationToggle: {})
    }

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
        .background(Color.cyBgSecondary)
        .widgetDetail(label: "Arrival", value: Self.spokenArrival(arrival, locale: locale, timeZone: timeZone), detail)
    }

    /// The hero's digits, and the day period as its unit — empty on a 24-hour clock.
    static func clockFace(_ date: Date, locale: Locale, timeZone: TimeZone) -> (time: String, dayPeriod: String) {
        let isTwelveHour = locale.hourCycle == .oneToTwelve || locale.hourCycle == .zeroToEleven
        // A 24-hour clock keeps its leading zero, "09:05", as the status bar's does; a 12-hour one
        // doesn't, "9:05".
        let hour: Date.FormatStyle.Symbol.Hour = isTwelveHour ? .defaultDigits(amPM: .omitted) : .twoDigits(amPM: .omitted)
        let time = date.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).hour(hour).minute(.twoDigits))
        guard isTwelveHour else { return (time, "") }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        let symbol = calendar.component(.hour, from: date) < 12 ? calendar.amSymbol : calendar.pmSymbol
        return (time, symbol.lowercased(with: locale))
    }

    /// What VoiceOver reads after "Arrival" (#361): "3:42 PM".
    static func spokenArrival(_ date: Date?, locale: Locale, timeZone: TimeZone) -> String {
        guard let date else { return "No reading" }
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone))
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
    ETAWidget(arrival: nil)
        .frame(width: 196, height: 96)
}

#Preview("12-Hour — Dark") {
    ETAWidget(arrival: previewArrival)
        .frame(width: 196, height: 96)
        .environment(\.locale, hourCycle(.oneToTwelve))
        .preferredColorScheme(.dark)
}
