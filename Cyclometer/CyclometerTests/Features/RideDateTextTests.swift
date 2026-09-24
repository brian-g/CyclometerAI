import Foundation
import Testing
@testable import Cyclometer

/// S14's row date (#248). Calendar, time zone and locale are pinned so the boundaries don't
/// move with the machine running the suite.
@Suite("RideDateText")
struct RideDateTextTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }()
    private static let locale = Locale(identifier: "en_US")

    /// Wednesday 23 September 2026, 10:00.
    private static let now = date(2026, 9, 23, 10, 0)

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// ICU puts a narrow no-break space (U+202F), not a space, before AM/PM — the
    /// expectations below spell it out so a mismatch doesn't hide in an invisible character.
    private func text(_ date: Date, now: Date = Self.now) -> String {
        RideDateText.text(for: date, now: now, calendar: Self.calendar, locale: Self.locale)
    }

    @Test("A ride earlier today reads \"Today\" with its time")
    func today() {
        #expect(text(Self.date(2026, 9, 23, 7, 5)) == "Today at 7:05\u{202F}AM")
    }

    @Test("A ride the previous day reads \"Yesterday\" with its time")
    func yesterday() {
        #expect(text(Self.date(2026, 9, 22, 14, 5)) == "Yesterday at 2:05\u{202F}PM")
    }

    @Test("Two to six days back reads as the weekday", arguments: [
        (21, "Monday 3:45\u{202F}PM"),
        (17, "Thursday 3:45\u{202F}PM")
    ])
    func weekday(day: Int, expected: String) {
        #expect(text(Self.date(2026, 9, day, 15, 45)) == expected)
    }

    /// Seven days back is the same weekday as today, so a weekday name would be ambiguous.
    @Test("Seven days back is absolute")
    func aWeekBack() {
        #expect(text(Self.date(2026, 9, 16, 15, 45)) == "Sep 16 at 3:45\u{202F}PM")
    }

    @Test("A ride in an earlier year carries the year")
    func earlierYear() {
        #expect(text(Self.date(2025, 12, 30, 8, 0)) == "Dec 30, 2025 at 8:00\u{202F}AM")
    }

    /// Counted in calendar days: a ride at 11 PM seen two hours later, after midnight, is
    /// yesterday's even though it was under a day ago.
    @Test("The boundary is midnight, not a 24-hour span")
    func calendarDayBoundary() {
        let justAfterMidnight = Self.date(2026, 9, 23, 1, 0)
        #expect(text(Self.date(2026, 9, 22, 23, 0), now: justAfterMidnight) == "Yesterday at 11:00\u{202F}PM")
        #expect(text(Self.date(2026, 9, 21, 23, 30), now: justAfterMidnight) == "Monday 11:30\u{202F}PM")
    }

    /// #291: the day word once came from the device clock, so these tests passed only on the
    /// day they were written. A `now` years from the clock's date proves it follows `now`.
    @Test("\"Today\" and \"Yesterday\" follow now, not the device clock")
    func relativeDayFollowsNow() {
        let farNow = Self.date(2031, 3, 12, 18, 0)
        #expect(text(Self.date(2031, 3, 12, 9, 15), now: farNow) == "Today at 9:15\u{202F}AM")
        #expect(text(Self.date(2031, 3, 11, 21, 40), now: farNow) == "Yesterday at 9:40\u{202F}PM")
    }

    @Test("Another locale keeps its own relative wording, and it too follows now")
    func relativeDayLocalized() {
        let farNow = Self.date(2031, 3, 12, 18, 0)
        let german = RideDateText.text(
            for: Self.date(2031, 3, 11, 14, 5), now: farNow,
            calendar: Self.calendar, locale: Locale(identifier: "de_DE")
        )
        #expect(german == "Gestern, 14:05")
    }

    @Test("A ride after now reads as today, not tomorrow")
    func rideAfterNowIsToday() {
        #expect(text(Self.date(2026, 9, 24, 0, 15)) == "Today at 12:15\u{202F}AM")
    }
}
