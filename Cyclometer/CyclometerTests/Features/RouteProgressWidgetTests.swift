import Foundation
import Testing
@testable import Cyclometer

/// #461 — W20's arrival, and how W19 and W20 read it out. `remainingDistanceMeters` itself is
/// driven through the route in `NavigationFeatureTests`.
@Suite("Route progress widgets")
struct RouteProgressWidgetTests {

    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let utc = TimeZone(identifier: "UTC")!

    /// 15:42 UTC.
    private let afternoon = Date(timeIntervalSince1970: 15 * 3_600 + 42 * 60)
    /// 09:05 UTC.
    private let morning = Date(timeIntervalSince1970: 9 * 3_600 + 5 * 60)

    private func locale(_ identifier: String, hourCycle: Locale.HourCycle? = nil) -> Locale {
        var components = Locale.Components(identifier: identifier)
        if let hourCycle { components.hourCycle = hourCycle }
        return Locale(components: components)
    }

    // MARK: - Arrival

    private func arrival(remaining: Double?, average: Double = 8, moving: Int = 600) -> Date? {
        ETADashboardWidget.arrival(now: now, remainingMeters: remaining, averageSpeedMPS: average, movingSeconds: moving)
    }

    @Test func noRouteHasNoArrival() {
        #expect(arrival(remaining: nil) == nil)
    }

    @Test func noMovingAverageYetHasNoArrival() {
        #expect(arrival(remaining: 12_000, average: 0, moving: 0) == nil)
    }

    /// The first seconds' average is barely above walking pace: no arrival until it has a minute.
    @Test func anUnsettledAverageHasNoArrival() {
        let settling = ETADashboardWidget.settlingSeconds
        #expect(arrival(remaining: 12_000, average: 1.5, moving: settling - 1) == nil)
        #expect(arrival(remaining: 12_000, average: 8, moving: settling) == now.addingTimeInterval(1_500))
    }

    @Test func midRouteArrivesAtTheMovingAverage() {
        // 12 km at 8 m/s: 25 minutes.
        #expect(arrival(remaining: 12_000) == now.addingTimeInterval(1_500))
    }

    /// The route reads 0 left once complete: there is nothing to arrive at, so W20 reads "—".
    @Test func completeHasNoArrival() {
        #expect(arrival(remaining: 0) == nil)
    }

    // MARK: - Clock face

    @Test func twelveHourClockTakesTheDayPeriodAsItsUnit() {
        let us = locale("en_US")
        #expect(ETAWidget.clockFace(afternoon, locale: us, timeZone: utc) == ("3:42", "pm"))
        #expect(ETAWidget.clockFace(morning, locale: us, timeZone: utc) == ("9:05", "am"))
    }

    @Test func twentyFourHourClockHasNoUnit() {
        #expect(ETAWidget.clockFace(afternoon, locale: locale("en_GB"), timeZone: utc) == ("15:42", ""))
        #expect(ETAWidget.clockFace(morning, locale: locale("en_GB"), timeZone: utc) == ("09:05", ""))
    }

    /// Each clock keeps its own hour digits and separator, as the status bar shows it.
    @Test func aTwentyFourHourClockKeepsTheLocalesOwnPattern() {
        #expect(ETAWidget.clockFace(morning, locale: locale("fi_FI"), timeZone: utc) == ("9.05", ""))
    }

    /// A day period written before the time comes out of the digits too.
    @Test func aLeadingDayPeriodIsTakenOut() {
        let face = ETAWidget.clockFace(afternoon, locale: locale("ko_KR"), timeZone: utc)
        #expect(face.time == "3:42")
        #expect(!face.dayPeriod.isEmpty)
    }

    /// The device's 24-Hour Time switch reaches the app as the locale's hour cycle.
    @Test func theDevicesHourSettingOverridesTheRegion() {
        let us24 = locale("en_US", hourCycle: .zeroToTwentyThree)
        #expect(ETAWidget.clockFace(afternoon, locale: us24, timeZone: utc) == ("15:42", ""))
        let gb12 = locale("en_GB", hourCycle: .oneToTwelve)
        #expect(ETAWidget.clockFace(afternoon, locale: gb12, timeZone: utc).time == "3:42")
        #expect(ETAWidget.clockFace(afternoon, locale: gb12, timeZone: utc).dayPeriod == "pm")
    }

    // MARK: - Spoken

    @Test func arrivalIsReadAsAClockTime() {
        #expect(ETAWidget.spokenArrival(afternoon, locale: locale("en_US"), timeZone: utc) == "3:42\u{202F}PM")
    }

    @Test func distanceRemainingIsReadInTheRidersUnits() {
        #expect(DistanceRemainingWidget(remainingMeters: 12_400, unit: .metric).accessibilityValue
            == "12.4 kilometers")
    }

    /// A route drawn on the map but not followed is not "No route" (#461 review).
    @Test func anEmptyReadingSaysWhy() {
        #expect(RouteProgressReading.empty(hasRoute: false, isTurnByTurnEnabled: true) == "No route")
        #expect(RouteProgressReading.empty(hasRoute: true, isTurnByTurnEnabled: false) == "Turn-by-turn off")
        #expect(RouteProgressReading.empty(hasRoute: true, isTurnByTurnEnabled: true) == "No reading")
        #expect(DistanceRemainingWidget(remainingMeters: nil, unit: .metric, isTurnByTurnEnabled: false)
            .accessibilityValue == "Turn-by-turn off")
    }
}
