import Foundation
import Synchronization

/// S14's row date: relative within the previous week, absolute beyond it (UX.md §S14).
///
/// Counted in calendar days, not 24-hour spans — a ride at 11 PM is "Yesterday" at 1 AM.
/// Pure, with `now`, calendar and locale passed in, so the boundaries can be asserted without
/// depending on when or where the tests run.
enum RideDateText {
    static func text(
        for date: Date,
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let daysAgo = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)
        ).day ?? 0

        switch daysAgo {
        case ...1:
            // The locale's own relative pattern, day word and time together: "Today at
            // 3:45 PM" in English, and whatever order and joiner another language uses.
            return relativeFormatted(date, calendar: calendar, locale: locale)
        case 2...6:
            return date.formatted(style(.dateTime.weekday(.wide).hour().minute(), calendar, locale))
        default:
            let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
            let absolute = Date.FormatStyle.dateTime.month(.abbreviated).day().hour().minute()
            return date.formatted(style(sameYear ? absolute : absolute.year(), calendar, locale))
        }
    }

    /// `DateFormatter` is the only API with relative day words ("Today", "Yesterday"), and
    /// it's costly to build, so one is kept per locale, calendar and time zone rather than
    /// made per row render (#248 review). Formatting happens under the lock: a
    /// `DateFormatter` isn't `Sendable`, so it never leaves it.
    private static let relativeFormatters = Mutex<[String: DateFormatter]>([:])

    private static func relativeFormatted(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        let key = "\(locale.identifier)|\(calendar.identifier)|\(calendar.timeZone.identifier)"
        return relativeFormatters.withLock { formatters in
            if let formatter = formatters[key] { return formatter.string(from: date) }
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            formatter.doesRelativeDateFormatting = true
            formatters[key] = formatter
            return formatter.string(from: date)
        }
    }

    private static func style(_ style: Date.FormatStyle, _ calendar: Calendar, _ locale: Locale) -> Date.FormatStyle {
        var style = style
        style.locale = locale
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return style
    }
}
