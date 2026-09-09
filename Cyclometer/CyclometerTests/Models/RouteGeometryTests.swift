import CoreLocation
import Foundation
import Testing
@testable import Cyclometer

@Suite("RouteGeometry")
struct RouteGeometryTests {

    private func coordinate(_ latitude: Double, _ longitude: Double, _ elevation: Double? = nil) -> RouteCoordinate {
        RouteCoordinate(latitude: latitude, longitude: longitude, elevationMeters: elevation)
    }

    /// A profile that only ever jitters, never climbs: alternating ±1 m about a level
    /// mean, well inside the 3 m deadband.
    private func jitteringProfile(count: Int) -> [RouteCoordinate] {
        (0..<count).map { index in
            coordinate(36.0 + Double(index) * 0.0001, -80.0, 200 + (index.isMultiple(of: 2) ? 1 : -1))
        }
    }

    // MARK: - Distance

    @Test("a single coordinate has no length")
    func distanceOfASingleCoordinateIsZero() {
        #expect(RouteGeometry.distanceMeters([coordinate(36, -80)]) == 0)
        #expect(RouteGeometry.distanceMeters([]) == 0)
    }

    @Test("one degree of meridian matches the WGS84 reference figure")
    func distanceOverAKnownMeridianSegment() {
        let distance = RouteGeometry.distanceMeters([coordinate(0, 0), coordinate(1, 0)])
        // 110,574.4 m is the published WGS84 value, not something read off this code.
        // A spherical approximation would give 111,195 m and fail here by 600 m.
        #expect(abs(distance - 110_574.4) < 1)
    }

    @Test("the same polyline always measures the same")
    func distanceIsDeterministic() {
        // `CLLocation.distance(from:)` was the first implementation and did not hold this:
        // it returned two answers for one polyline inside a single test process. A stored,
        // displayed, filtered-on number has to be reproducible.
        let route = (0..<200).map { coordinate(36.0 + Double($0) * 0.0001, -80.0 + Double($0) * 0.0001) }
        let measurements = Set((0..<50).map { _ in RouteGeometry.distanceMeters(route) })
        #expect(measurements.count == 1)
    }

    @Test("distance accumulates every segment, not just the endpoints")
    func distanceAccumulatesEverySegment() {
        let leg = RouteGeometry.distanceMeters([coordinate(36.00, -80), coordinate(36.01, -80)])
        let twoLegs = RouteGeometry.distanceMeters([
            coordinate(36.00, -80), coordinate(36.01, -80), coordinate(36.02, -80),
        ])
        #expect(abs(twoLegs - 2 * leg) < 1)
    }

    // MARK: - Elevation

    @Test("a route where no point carries an elevation reports nil, not zero")
    func elevationIsNilWhenNoCoordinateCarriesElevation() {
        let result = RouteGeometry.elevationGainLoss([
            coordinate(36.0, -80), coordinate(36.1, -80), coordinate(36.2, -80),
        ])
        #expect(result == nil)
    }

    @Test("a single elevation sample reports nil — one point has no delta to measure")
    func elevationIsNilWhenOnlyOneCoordinateCarriesElevation() {
        let result = RouteGeometry.elevationGainLoss([
            coordinate(36.0, -80, 200), coordinate(36.1, -80), coordinate(36.2, -80),
        ])
        #expect(result == nil)
    }

    @Test("a genuinely flat route with elevations reports zero, not nil")
    func aFlatRouteWithElevationsReportsZeroNotNil() throws {
        let result = try #require(RouteGeometry.elevationGainLoss([
            coordinate(36.0, -80, 200), coordinate(36.1, -80, 200), coordinate(36.2, -80, 200),
        ]))
        #expect(result.gain == 0)
        #expect(result.loss == 0)
    }

    @Test("jitter below the threshold accumulates nothing")
    func elevationIgnoresJitterBelowTheThreshold() throws {
        // The test a raw positive-delta sum fails: 200 alternating ±1 m steps would
        // report ~200 m of climbing on a level road.
        let result = try #require(RouteGeometry.elevationGainLoss(jitteringProfile(count: 200)))
        #expect(result.gain == 0)
        #expect(result.loss == 0)
    }

    @Test("a long climb of sub-threshold steps still banks its full height")
    func elevationAccumulatesAClimbMadeOfSubThresholdSteps() throws {
        // The test a per-delta filter fails: every step is 0.5 m, under the 3 m floor, but
        // the climb is 500 m. Only a *moving reference* accumulates this.
        let climb = (0...1000).map { coordinate(36.0 + Double($0) * 0.0001, -80.0, 200 + Double($0) * 0.5) }
        let result = try #require(RouteGeometry.elevationGainLoss(climb))
        #expect(abs(result.gain - 500) < RouteGeometry.elevationNoiseThresholdMeters)
        #expect(result.loss == 0)
    }

    @Test("gain and loss are counted independently on an out-and-back")
    func elevationSeparatesGainFromLoss() throws {
        let result = try #require(RouteGeometry.elevationGainLoss([
            coordinate(36.0, -80, 100),
            coordinate(36.1, -80, 300),
            coordinate(36.2, -80, 150),
        ]))
        #expect(result.gain == 200)
        #expect(result.loss == 150)
    }

    @Test("a move exactly at the threshold is banked; one just under it is not")
    func elevationThresholdIsInclusiveAtItsBoundary() throws {
        let threshold = RouteGeometry.elevationNoiseThresholdMeters
        let atThreshold = try #require(RouteGeometry.elevationGainLoss([
            coordinate(36.0, -80, 100), coordinate(36.1, -80, 100 + threshold),
        ]))
        #expect(atThreshold.gain == threshold)

        let justUnder = try #require(RouteGeometry.elevationGainLoss([
            coordinate(36.0, -80, 100), coordinate(36.1, -80, 100 + threshold - 0.01),
        ]))
        #expect(justUnder.gain == 0)
    }

    @Test("elevation is measured over only the points that carry one")
    func elevationUsesOnlyTheCoordinatesThatCarryIt() throws {
        let result = try #require(RouteGeometry.elevationGainLoss([
            coordinate(36.0, -80, 100),
            coordinate(36.1, -80, nil),
            coordinate(36.2, -80, 250),
        ]))
        #expect(result.gain == 150)
        #expect(result.loss == 0)
    }

    // MARK: - Bounding box

    @Test("the bounding box spans the extremes of the polyline")
    func boundingBoxSpansEveryPoint() {
        let bounds = RouteGeometry.boundingBox([
            coordinate(36.1, -80.5),
            coordinate(36.4, -80.1),
            coordinate(35.9, -80.9),
            coordinate(36.2, -80.3),
        ])
        #expect(bounds == RouteBounds(
            minLatitude: 35.9, maxLatitude: 36.4,
            minLongitude: -80.9, maxLongitude: -80.1
        ))
    }

    @Test("a single coordinate yields a degenerate box at that point")
    func boundingBoxOfASingleCoordinateIsDegenerate() {
        let bounds = RouteGeometry.boundingBox([coordinate(36.1, -80.5)])
        #expect(bounds == RouteBounds(
            minLatitude: 36.1, maxLatitude: 36.1,
            minLongitude: -80.5, maxLongitude: -80.5
        ))
    }
}
