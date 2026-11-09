import Foundation
import Testing
@testable import Cyclometer

@Suite("RideDurationEstimate")
struct RideDurationEstimateTests {

    private static let route = 40_000.0

    private static func routeRide(meters: Double, seconds: TimeInterval) -> RouteRideSummary {
        RouteRideSummary(rideId: UUID(), title: "", startedAt: .distantPast, endedAt: nil,
                         durationSeconds: seconds, distanceMeters: meters)
    }

    private static func ride(meters: Double, seconds: TimeInterval) -> RideListSummary {
        RideListSummary(id: UUID(), title: "", startedAt: .distantPast, distanceMeters: meters, durationSeconds: seconds)
    }

    @Test("Earlier rides of the route: the route's distance at their median speed")
    func medianOfRouteRides() {
        // 5, 6 and 8 m/s: the median is 6, so 40 km takes 6,667 s. The 8 m/s outlier moves nothing.
        let rides = [Self.routeRide(meters: 40_000, seconds: 8_000),
                     Self.routeRide(meters: 40_000, seconds: 5_000),
                     Self.routeRide(meters: 36_000, seconds: 6_000)]
        let seconds = RideDurationEstimate.seconds(routeDistanceMeters: Self.route, routeRides: rides, recentRides: [])
        #expect(seconds == Self.route / 6)
    }

    @Test("An even count takes the mean of the middle two speeds")
    func evenMedian() {
        let rides = [Self.routeRide(meters: 40_000, seconds: 10_000),   // 4 m/s
                     Self.routeRide(meters: 40_000, seconds: 5_000)]    // 8 m/s
        #expect(RideDurationEstimate.seconds(routeDistanceMeters: Self.route, routeRides: rides, recentRides: []) == Self.route / 6)
    }

    @Test("A ride abandoned halfway still counts for the full route's time")
    func partialRouteRide() {
        // Half the route in half the time a full ride takes: the same 5 m/s.
        let rides = [Self.routeRide(meters: 20_000, seconds: 4_000)]
        #expect(RideDurationEstimate.seconds(routeDistanceMeters: Self.route, routeRides: rides, recentRides: []) == 8_000)
    }

    @Test("Route rides beat recent riding elsewhere")
    func routeRidesFirst() {
        let seconds = RideDurationEstimate.seconds(
            routeDistanceMeters: Self.route,
            routeRides: [Self.routeRide(meters: 40_000, seconds: 8_000)],
            recentRides: [Self.ride(meters: 10_000, seconds: 1_000)]
        )
        #expect(seconds == 8_000)
    }

    @Test("No rides of the route: the overall speed of the last ten rides")
    func recentRidesFallback() {
        // Ten rides at 5 m/s, then an eleventh — older, past the cap — at 1 m/s.
        let recent = Array(repeating: Self.ride(meters: 10_000, seconds: 2_000), count: RideDurationEstimate.recentRideCount)
            + [Self.ride(meters: 1_000, seconds: 1_000)]
        #expect(RideDurationEstimate.seconds(routeDistanceMeters: Self.route, routeRides: [], recentRides: recent) == 8_000)
    }

    @Test("Overall speed weights rides by their length, not one ride one vote")
    func recentRidesAggregate() {
        // 30 km in 6,000 s and 10 km in 4,000 s: 40 km in 10,000 s is 4 m/s.
        let recent = [Self.ride(meters: 30_000, seconds: 6_000), Self.ride(meters: 10_000, seconds: 4_000)]
        #expect(RideDurationEstimate.seconds(routeDistanceMeters: Self.route, routeRides: [], recentRides: recent) == 10_000)
    }

    @Test("Rides with no distance or no time are skipped")
    func emptyRidesSkipped() {
        let seconds = RideDurationEstimate.seconds(
            routeDistanceMeters: Self.route,
            routeRides: [Self.routeRide(meters: 0, seconds: 600), Self.routeRide(meters: 500, seconds: 0)],
            recentRides: [Self.ride(meters: 0, seconds: 300), Self.ride(meters: 20_000, seconds: 4_000)]
        )
        #expect(seconds == 8_000)
    }

    @Test("Nothing to go on is no estimate")
    func noRides() {
        #expect(RideDurationEstimate.seconds(routeDistanceMeters: Self.route, routeRides: [], recentRides: []) == nil)
        #expect(RideDurationEstimate.seconds(routeDistanceMeters: 0, routeRides: [Self.routeRide(meters: 1, seconds: 1)], recentRides: []) == nil)
    }
}

@Suite("CompassPoint")
struct CompassPointTests {

    @Test("A bearing rounds to the nearest of eight points", arguments: [
        (0.0, CompassPoint.north), (22.4, .north), (22.5, .northEast), (90, .east), (135, .southEast),
        (180, .south), (225, .southWest), (270, .west), (315, .northWest), (337.5, .north), (359, .north),
    ] as [(Double, CompassPoint)])
    func rounding(_ degrees: Double, _ expected: CompassPoint) {
        #expect(CompassPoint(degrees: degrees) == expected)
    }

    @Test("Angles outside 0..<360 wrap")
    func wrapping() {
        #expect(CompassPoint(degrees: -90) == .west)
        #expect(CompassPoint(degrees: 360) == .north)
        #expect(CompassPoint(degrees: 450) == .east)
    }

    @Test("A non-finite bearing is north, not a trap")
    func nonFinite() {
        #expect(CompassPoint(degrees: .nan) == .north)
        #expect(CompassPoint(degrees: .infinity) == .north)
    }
}

@Suite("WeatherCondition display")
struct WeatherConditionDisplayTests {

    @Test("Clear and partly cloudy skies have a night form; the rest don't")
    func nightForms() {
        #expect(WeatherCondition.clear.symbolName(isDaylight: false) == "moon.stars.fill")
        #expect(WeatherCondition.partlyCloudy.symbolName(isDaylight: false) == "cloud.moon.fill")
        #expect(WeatherCondition.rain.symbolName(isDaylight: false) == WeatherCondition.rain.symbolName(isDaylight: true))
    }
}
