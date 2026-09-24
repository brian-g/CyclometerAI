import Foundation
import Synchronization

/// S14's row date: relative within the previous week, absolute beyond it (UX.md §S14).
///
/// Counted in calendar days, not 24-hour spans — a ride at 11 PM is "Yesterday" at 1 AM.
/// `now`, calendar and locale are passed in, so the boundaries can be asserted without
/// depending on when or where the tests run. Not pure: "Today" and "Yesterday" come from a
/// formatter that only knows the device clock, so that branch reads the clock to shift the
/// ride onto it (#291).
enum RideDateText {
    static func text(
        for date: Date,
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        // A ride after `now` (the device clock set back, say) reads as today, not "Tomorrow".
        let daysAgo = max(calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)
        ).day ?? 0, 0)

        switch daysAgo {
        case 0...1:
            // The locale's own relative pattern, day word and time together: "Today at
            // 3:45 PM" in English, and whatever order and joiner another language uses.
            return relativeFormatted(date, daysAgo: daysAgo, calendar: calendar, locale: locale)
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

    /// The formatter picks its day word against the device clock, not `now` (#291). So the ride's
    /// time of day is moved onto the day `daysAgo` before the clock's today, and the formatter
    /// names the day `now` meant. A spring-forward gap on that day could shift the printed hour
    /// for a ride inside it, the one case the move can't carry over.
    private static func relativeFormatted(_ date: Date, daysAgo: Int, calendar: Calendar, locale: Locale) -> String {
        let time = calendar.dateComponents([.hour, .minute, .second], from: date)
        let clockToday = calendar.startOfDay(for: Date())
        let shifted = calendar.date(byAdding: .day, value: -daysAgo, to: clockToday).flatMap {
            calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: $0)
        } ?? date
        let key = "\(locale.identifier)|\(calendar.identifier)|\(calendar.timeZone.identifier)"
        return relativeFormatters.withLock { formatters in
            if let formatter = formatters[key] { return formatter.string(from: shifted) }
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            formatter.doesRelativeDateFormatting = true
            formatters[key] = formatter
            return formatter.string(from: shifted)
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
