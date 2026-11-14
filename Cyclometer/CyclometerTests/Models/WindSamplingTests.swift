import Foundation
import Testing
@testable import Cyclometer

/// #561 — where the wind map samples, and which answer it draws.
@Suite("WindSampling")
struct WindSamplingTests {

    // MARK: - How many, and where

    /// One per 10 km of the distance left, both ends counted, between 2 and 8.
    @Test("Sample count follows the route's length, from 2 to 8", arguments: [
        (5_000.0, 2), (10_000.0, 2), (25_000.0, 4), (60_000.0, 7), (100_000.0, 8), (200_000.0, 8),
    ])
    func counts(totalMeters: Double, expected: Int) {
        let distances = WindSampling.distances(totalMeters: totalMeters)
        #expect(distances.count == expected)
        #expect(distances.first == 0)
        #expect(distances.last == totalMeters, "the finish is sampled")
    }

    /// Measured distances carry floating-point noise: a fraction of a metre over 10 km is 10 km.
    @Test("Up to a metre past a multiple of 10 km earns no extra sample; more than that does")
    func tolerance() {
        #expect(WindSampling.distances(totalMeters: 20_000.0001).count == 3)
        #expect(WindSampling.distances(totalMeters: 20_000 + WindSampling.spacingToleranceMeters).count == 3)
        #expect(WindSampling.distances(totalMeters: 20_002).count == 4)
    }

    @Test("Samples are evenly spaced")
    func evenlySpaced() {
        #expect(WindSampling.distances(totalMeters: 25_000) == [0, 25_000.0 / 3, 50_000.0 / 3, 25_000])
    }

    /// A loop ends where it began, so its finish would ask about the start a second time.
    @Test("A loop from its start leaves out the finish: two samples are the start and halfway")
    func loop() {
        #expect(WindSampling.distances(totalMeters: 8_000, isLoop: true) == [0, 4_000])
        let long = WindSampling.distances(totalMeters: 100_000, isLoop: true)
        #expect(long.count == WindSampling.maximumSamples)
        #expect(long.last == 87_500)
    }

    @Test("Mid-route, only the distance left is sampled, from where the rider is to the finish")
    func fromProgress() {
        #expect(WindSampling.distances(totalMeters: 50_000, fromMeters: 30_000) == [30_000, 40_000, 50_000])
        // On a loop the finish is ahead of a rider partway round, so it counts.
        #expect(WindSampling.distances(totalMeters: 50_000, fromMeters: 30_000, isLoop: true) == [30_000, 40_000, 50_000])
    }

    @Test("Progress past the finish, or a route with no length, is one sample")
    func degenerate() {
        #expect(WindSampling.distances(totalMeters: 50_000, fromMeters: 60_000) == [50_000])
        #expect(WindSampling.distances(totalMeters: 0) == [0])
    }

    // MARK: - When

    @Test("Each point is timed at the speed from where sampling starts")
    func arrivals() {
        let route = RouteFixtures.path(legs: [(0, 25_000)], spacingMeters: 100)
        let cumulative = RouteGeometry.cumulativeDistances(route)
        let start = WeatherReading.fixtureNow
        let points = WindSampling.points(coordinates: route, cumulative: cumulative, start: start, speedMPS: 5)
        #expect(points.count == 4)
        #expect(points[0].coordinate == route[0])
        #expect(points[0].arrival == start)
        for point in points {
            #expect(abs(point.arrival.timeIntervalSince(start) - point.distanceMeters / 5) < 0.001)
        }
        #expect(points.last.map { RouteGeometry.distanceMeters([$0.coordinate, route[route.count - 1]]) < 1 } == true)
    }

    @Test("Mid-route, the clock starts where the rider is, not at the route's start")
    func arrivalsFromProgress() {
        let route = RouteFixtures.path(legs: [(90, 20_000)], spacingMeters: 100)
        let cumulative = RouteGeometry.cumulativeDistances(route)
        let start = WeatherReading.fixtureNow
        let points = WindSampling.points(coordinates: route, cumulative: cumulative, fromMeters: 10_000,
                                         start: start, speedMPS: 10)
        #expect(points.map(\.arrival) == [start, start.addingTimeInterval(1_000)])
    }

    /// The speed a route is ridden at in its estimate, which the hourly strip also assumes.
    @Test("The route's speed comes from its estimate, the default window, and the 12-hour cap")
    func speed() {
        #expect(WindSampling.speedMPS(routeDistanceMeters: 36_000, estimate: 7_200) == 5)
        #expect(WindSampling.speedMPS(routeDistanceMeters: 36_000, estimate: nil) == 36_000 / AttributedForecast.defaultRideWindow)
        #expect(WindSampling.speedMPS(routeDistanceMeters: 36_000, estimate: 100 * 3600)
                == 36_000 / AttributedForecast.maximumRideWindow)
    }

    // MARK: - Which reading

    /// The fixture's current conditions are observed at 14:00; its hours run 14:00 to 01:00.
    private static let base = WeatherReading.fixtureDate
    private func reading(at offset: TimeInterval) -> WeatherReading? {
        WindSampling.reading(at: Self.base.addingTimeInterval(offset),
                             current: .fixture, hourly: WeatherReading.fixtureHourly)
    }

    @Test("Within the hour the current conditions were observed in, they are the reading")
    func currentHour() {
        #expect(reading(at: 0) == .fixture)
        #expect(reading(at: 3_599) == .fixture)
        #expect(reading(at: -60) == .fixture, "before the forecast's first hour is now")
    }

    @Test("Later, the forecast hour containing the arrival; its start belongs to it")
    func forecastHour() {
        #expect(reading(at: 3_600) == WeatherReading.fixtureHourly[1])
        #expect(reading(at: 5 * 3_600 + 1_800) == WeatherReading.fixtureHourly[5])
        #expect(reading(at: 11 * 3_600 + 3_599) == WeatherReading.fixtureHourly[11])
    }

    @Test("Past the end of the forecast there is no reading")
    func pastTheForecast() {
        #expect(reading(at: 12 * 3_600) == nil)
    }

    // MARK: - Free-ride field

    @Test("The field is an even grid inside the visible bounds, rows following the map's shape")
    func field() {
        let center = RouteFixtures.origin
        let southWest = RouteGeometry.coordinate(offsetFrom: center, north: -1_100, east: -1_800)
        let northEast = RouteGeometry.coordinate(offsetFrom: center, north: 1_100, east: 1_800)
        let bounds = RouteBounds(minLatitude: southWest.latitude, maxLatitude: northEast.latitude,
                                 minLongitude: southWest.longitude, maxLongitude: northEast.longitude)
        let field = WindSampling.field(in: bounds)
        // 3.6 km by 2.2 km: four columns, two rows.
        #expect(field.count == WindSampling.fieldColumns * 2)
        for point in field {
            #expect(point.latitude > bounds.minLatitude && point.latitude < bounds.maxLatitude)
            #expect(point.longitude > bounds.minLongitude && point.longitude < bounds.maxLongitude)
        }
        // Even columns and rows: nothing at the centre, under the rider's dot.
        #expect(!field.contains { RouteGeometry.distanceMeters([$0, center]) < 100 })
    }

    @Test("Bounds with no area have no field")
    func emptyField() {
        let point = RouteFixtures.origin
        let bounds = RouteBounds(minLatitude: point.latitude, maxLatitude: point.latitude,
                                 minLongitude: point.longitude, maxLongitude: point.longitude)
        #expect(WindSampling.field(in: bounds).isEmpty)
    }
}

/// #561 — the wind map's arrow.
@Suite("WindArrowGeometry")
struct WindArrowGeometryTests {

    private static let center = RouteFixtures.origin

    @Test("Below the calm threshold there is no arrow")
    func calm() {
        #expect(WindArrowGeometry.lengthPoints(speedMPS: 0) == nil)
        #expect(WindArrowGeometry.lengthPoints(speedMPS: RideWindExposure.calmMPS - 0.01) == nil)
        #expect(WindArrowGeometry.polygon(center: Self.center, windFromDegrees: 0, speedMPS: 0.2, metersPerPoint: 1) == nil)
    }

    @Test("Length grows with the wind, from the minimum to the maximum, and stops there")
    func length() throws {
        let light = try #require(WindArrowGeometry.lengthPoints(speedMPS: RideWindExposure.calmMPS))
        let middling = try #require(WindArrowGeometry.lengthPoints(speedMPS: 6))
        let gale = try #require(WindArrowGeometry.lengthPoints(speedMPS: 30))
        #expect(light == WindArrowGeometry.minimumLengthPoints)
        #expect(middling > light && middling < gale)
        #expect(gale == WindArrowGeometry.maximumLengthPoints)
        #expect(WindArrowGeometry.lengthPoints(speedMPS: WindArrowGeometry.fullLengthMPS) == gale)
    }

    /// A northerly comes from the north, so it blows south: the tip is south of the tail.
    @Test("The arrow points the way the wind blows", arguments: [
        (0.0, 180.0), (90.0, 270.0), (180.0, 0.0), (270.0, 90.0), (225.0, 45.0),
    ])
    func pointsDownwind(from: Double, toward: Double) throws {
        let polygon = try #require(WindArrowGeometry.polygon(
            center: Self.center, windFromDegrees: from, speedMPS: 6, metersPerPoint: 2
        ))
        #expect(polygon.count == 7)
        let bearing = try #require(RouteGeometry.bearingDegrees(from: Self.center, to: polygon[0]))
        #expect(abs(((bearing - toward + 540).truncatingRemainder(dividingBy: 360)) - 180) < 0.5)
    }

    @Test("Its size on the ground is its size in points at the map's scale")
    func scale() throws {
        let length = try #require(WindArrowGeometry.lengthPoints(speedMPS: 6))
        for metersPerPoint in [1.0, 20.0] {
            let polygon = try #require(WindArrowGeometry.polygon(
                center: Self.center, windFromDegrees: 0, speedMPS: 6, metersPerPoint: metersPerPoint
            ))
            let tipToTail = RouteGeometry.distanceMeters([polygon[0], polygon[3]])
            // The tail's corner is half a shaft off the axis: well under a point.
            #expect(abs(tipToTail - length * metersPerPoint) < metersPerPoint)
        }
    }
}
