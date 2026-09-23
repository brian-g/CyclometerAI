import Foundation

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
            // "Today 3:45 PM" as Design.sketch draws it. The system's combined relative
            // style reads "Today at 3:45 PM", so the localized day word is taken on its own.
            let day = DateFormatter()
            day.locale = locale
            day.calendar = calendar
            day.timeZone = calendar.timeZone
            day.dateStyle = .medium
            day.timeStyle = .none
            day.doesRelativeDateFormatting = true
            return "\(day.string(from: date)) \(date.formatted(style(.dateTime.hour().minute(), calendar, locale)))"
        case 2...6:
            return date.formatted(style(.dateTime.weekday(.wide).hour().minute(), calendar, locale))
        default:
            let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
            let absolute = Date.FormatStyle.dateTime.month(.abbreviated).day().hour().minute()
            return date.formatted(style(sameYear ? absolute : absolute.year(), calendar, locale))
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
