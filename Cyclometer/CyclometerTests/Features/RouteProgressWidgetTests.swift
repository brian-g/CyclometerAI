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

    @Test func noRouteHasNoArrival() {
        #expect(ETADashboardWidget.arrival(now: now, remainingMeters: nil, averageSpeedMPS: 8) == nil)
    }

    @Test func noMovingAverageYetHasNoArrival() {
        #expect(ETADashboardWidget.arrival(now: now, remainingMeters: 12_000, averageSpeedMPS: 0) == nil)
    }

    @Test func midRouteArrivesAtTheMovingAverage() {
        // 12 km at 8 m/s: 25 minutes.
        #expect(ETADashboardWidget.arrival(now: now, remainingMeters: 12_000, averageSpeedMPS: 8)
            == now.addingTimeInterval(1_500))
    }

    /// The route reads 0 left once complete: there is nothing to arrive at, so W20 reads "—".
    @Test func completeHasNoArrival() {
        #expect(ETADashboardWidget.arrival(now: now, remainingMeters: 0, averageSpeedMPS: 8) == nil)
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
        #expect(ETAWidget.spokenArrival(nil, locale: locale("en_US"), timeZone: utc) == "No reading")
    }

    @Test func distanceRemainingIsReadInTheRidersUnits() {
        #expect(DistanceRemainingWidget(remainingMeters: 12_400, unit: .metric).accessibilityValue
            == "12.4 kilometers")
        #expect(DistanceRemainingWidget(remainingMeters: nil, unit: .metric).accessibilityValue == "No route")
    }
}
