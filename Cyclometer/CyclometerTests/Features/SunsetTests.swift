import Foundation
import Testing
@testable import Cyclometer

/// #462 — W21's sunset and countdown. Expected sunsets are NOAA's own: its Solar Calculator's
/// `calcSunriseSetUTC` two-pass flow (gml.noaa.gov/grad/solcalc/main.js), run in node and rounded
/// to the minute as the calculator shows it.
@Suite("Sunset")
struct SunsetTests {

    private static let boulder = Coordinate(latitude: 40.0150, longitude: -105.2705)
    private static let reykjavik = Coordinate(latitude: 64.1466, longitude: -21.9426)
    private static let tromso = Coordinate(latitude: 69.6492, longitude: 18.9553)

    private static func utc(_ iso: String) -> Date {
        try! Date(iso, strategy: .iso8601)
    }

    // MARK: - NOAA

    struct Case: CustomTestStringConvertible, Sendable {
        let place: String
        let coordinate: Coordinate
        let year, month, day: Int
        let sunset: String?

        var testDescription: String { "\(place) \(year)-\(month)-\(day)" }
    }

    static let noaa: [Case] = [
        Case(place: "Boulder", coordinate: boulder, year: 2026, month: 6, day: 21, sunset: "2026-06-22T02:34:00Z"),
        Case(place: "Boulder", coordinate: boulder, year: 2026, month: 12, day: 21, sunset: "2026-12-21T23:39:00Z"),
        Case(
            place: "Sydney", coordinate: Coordinate(latitude: -33.8688, longitude: 151.2093),
            year: 2026, month: 12, day: 21, sunset: "2026-12-21T09:05:00Z"
        ),
        Case(
            place: "Sydney", coordinate: Coordinate(latitude: -33.8688, longitude: 151.2093),
            year: 2026, month: 6, day: 21, sunset: "2026-06-21T06:54:00Z"
        ),
        Case(
            place: "Quito", coordinate: Coordinate(latitude: -0.1807, longitude: -78.4678),
            year: 2026, month: 3, day: 20, sunset: "2026-03-20T23:24:00Z"
        ),
        // The day the clocks go forward: the instant doesn't care.
        Case(
            place: "London", coordinate: Coordinate(latitude: 51.5074, longitude: -0.1278),
            year: 2026, month: 3, day: 29, sunset: "2026-03-29T18:29:00Z"
        ),
        // After midnight, local and UTC.
        Case(place: "Reykjavik", coordinate: reykjavik, year: 2026, month: 6, day: 21, sunset: "2026-06-22T00:04:00Z"),
        Case(
            place: "Ushuaia", coordinate: Coordinate(latitude: -54.8019, longitude: -68.3030),
            year: 2026, month: 12, day: 21, sunset: "2026-12-22T01:11:00Z"
        ),
        // After the next UTC midnight, and east of it before: both sides of the date line.
        Case(
            place: "Honolulu", coordinate: Coordinate(latitude: 21.3069, longitude: -157.8583),
            year: 2026, month: 10, day: 28, sunset: "2026-10-29T03:57:00Z"
        ),
        Case(
            place: "Auckland", coordinate: Coordinate(latitude: -36.8485, longitude: 174.7633),
            year: 2026, month: 10, day: 28, sunset: "2026-10-28T06:49:00Z"
        ),
        // Polar day and polar night.
        Case(place: "Tromsø", coordinate: tromso, year: 2026, month: 6, day: 21, sunset: nil),
        Case(place: "Tromsø", coordinate: tromso, year: 2026, month: 12, day: 21, sunset: nil),
    ]

    @Test("The sunset is NOAA's, to the minute", arguments: noaa)
    func matchesNOAA(_ noaa: Case) {
        let sunset = Sunset.sunset(year: noaa.year, month: noaa.month, day: noaa.day, at: noaa.coordinate)
        #expect(sunset == noaa.sunset.map(Self.utc))
    }

    // MARK: - Countdown

    private static let denver = TimeZone(identifier: "America/Denver")!

    private func countdown(_ now: String, at coordinate: Coordinate? = boulder, in timeZone: TimeZone = denver)
        -> Sunset.Countdown {
        Sunset.countdown(now: Self.utc(now), coordinate: coordinate, timeZone: timeZone)
    }

    @Test func noFixHasNoCountdown() {
        #expect(countdown("2026-06-22T01:22:00Z", at: nil) == .noFix)
    }

    /// 19:22 MDT, with sunset at 20:34.
    @Test func countsTheMinutesToSunset() {
        #expect(countdown("2026-06-22T01:22:00Z") == .minutesLeft(72))
    }

    /// The sunset is to the minute, so the countdown turns over on the clock's minute.
    @Test func turnsOverOnTheClocksMinute() {
        #expect(countdown("2026-06-22T01:22:59Z") == .minutesLeft(72))
        #expect(countdown("2026-06-22T01:23:00Z") == .minutesLeft(71))
    }

    /// It reads 0:01 in the minute before sunset, and never 0:00.
    @Test func sunsetsMinuteHasPassed() {
        #expect(countdown("2026-06-22T02:33:59Z") == .minutesLeft(1))
        #expect(countdown("2026-06-22T02:34:00Z") == .passed)
        #expect(countdown("2026-06-22T05:59:00Z") == .passed)
    }

    /// 00:30 MDT: a new day, and its sunset.
    @Test func midnightStartsTheNextDaysCountdown() {
        #expect(countdown("2026-06-22T06:30:00Z") == .minutesLeft(20 * 60 + 4))
    }

    /// At 00:01, Reykjavik's sunset for the 21st is still three minutes off. Once it has set, the
    /// 22nd's, at 00:04 on the 23rd, is ahead: near midsummer it never reads "—".
    @Test func yesterdaysSunsetCountsWhileItIsAhead() {
        let iceland = TimeZone(identifier: "Atlantic/Reykjavik")!
        #expect(countdown("2026-06-22T00:01:00Z", at: Self.reykjavik, in: iceland) == .minutesLeft(3))
        #expect(countdown("2026-06-22T00:04:00Z", at: Self.reykjavik, in: iceland) == .minutesLeft(24 * 60))
    }

    /// The device's time zone decides what "today" is: one instant is after the 21st's sunset in
    /// Denver, and the afternoon of the 22nd in Tokyo.
    @Test func theDevicesTimeZoneDecidesToday() {
        #expect(countdown("2026-06-22T05:00:00Z") == .passed)
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        #expect(countdown("2026-06-22T05:00:00Z", in: tokyo) == .minutesLeft(21 * 60 + 34))
    }

    @Test func polarDayHasNoSunset() {
        let norway = TimeZone(identifier: "Europe/Oslo")!
        #expect(countdown("2026-06-21T12:00:00Z", at: Self.tromso, in: norway) == .noSunset)
    }

    // MARK: - Widget

    @Test func voiceOverReadsTheCountdown() {
        #expect(SunsetWidget(countdown: .minutesLeft(72)).accessibilityValue == "in 1 hour, 12 minutes")
        #expect(SunsetWidget(countdown: .minutesLeft(8)).accessibilityValue == "in 8 minutes")
        #expect(SunsetWidget(countdown: .passed).accessibilityValue == "After sunset")
        #expect(SunsetWidget(countdown: .noSunset).accessibilityValue == "No sunset today")
        #expect(SunsetWidget(countdown: .noFix).accessibilityValue == "No location")
    }
}
