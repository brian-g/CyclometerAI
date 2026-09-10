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

/// #194 — deciding what a map viewport holds.
///
/// The interesting fixtures here are the two a *bounding-box* test cannot tell apart from the
/// real thing: a viewport sitting inside a loop, and one in the empty corner of a diagonal.
/// Both have a route whose stored box overlaps the viewport while none of the drawn line does,
/// and both are what "show only those routes displayed on the map" actually means.
@Suite("RouteGeometry — viewport intersection")
struct RouteGeometryViewportTests {

    private func coordinate(_ latitude: Double, _ longitude: Double) -> RouteCoordinate {
        RouteCoordinate(latitude: latitude, longitude: longitude, elevationMeters: nil)
    }

    /// A small viewport somewhere in the middle of everything below.
    private let viewport = RouteBounds(
        minLatitude: 37.40, maxLatitude: 37.50,
        minLongitude: -122.10, maxLongitude: -122.00
    )

    // MARK: - RouteBounds.intersects

    @Test("boxes that overlap intersect, and boxes that miss do not")
    func boundsOverlap() {
        let overlapping = RouteBounds(minLatitude: 37.45, maxLatitude: 37.60,
                                      minLongitude: -122.05, maxLongitude: -121.90)
        let disjoint = RouteBounds(minLatitude: 38.00, maxLatitude: 38.10,
                                   minLongitude: -122.05, maxLongitude: -121.95)
        #expect(viewport.intersects(overlapping))
        #expect(overlapping.intersects(viewport))
        #expect(!viewport.intersects(disjoint))
    }

    @Test("boxes that share only an edge intersect")
    func boundsTouchingAnEdgeIntersect() {
        // A route whose easternmost point lies exactly on the viewport's western edge is drawn
        // on that edge, so the list has to agree it is visible.
        let touching = RouteBounds(minLatitude: 37.40, maxLatitude: 37.50,
                                   minLongitude: -122.30, maxLongitude: -122.10)
        #expect(viewport.intersects(touching))
    }

    @Test("contains is strict about holding all of the other box")
    func boundsContainment() {
        let inside = RouteBounds(minLatitude: 37.42, maxLatitude: 37.48,
                                 minLongitude: -122.08, maxLongitude: -122.02)
        let straddling = RouteBounds(minLatitude: 37.42, maxLatitude: 37.60,
                                     minLongitude: -122.08, maxLongitude: -122.02)
        #expect(viewport.contains(inside))
        #expect(!viewport.contains(straddling))
        #expect(viewport.contains(latitude: 37.45, longitude: -122.05))
        #expect(!viewport.contains(latitude: 37.45, longitude: -121.00))
    }

    // MARK: - The written acceptance criteria

    @Test("a route wholly inside the viewport is kept")
    func routeWhollyInsideIsKept() {
        let route = [coordinate(37.42, -122.08), coordinate(37.45, -122.05), coordinate(37.48, -122.02)]
        #expect(RouteGeometry.polyline(route, intersects: viewport))
    }

    @Test("a route wholly outside the viewport is dropped")
    func routeWhollyOutsideIsDropped() {
        let route = [coordinate(38.10, -121.00), coordinate(38.20, -120.90)]
        #expect(!RouteGeometry.polyline(route, intersects: viewport))
    }

    @Test("a route that merely crosses the viewport, both endpoints outside, is kept")
    func routeCrossingWithBothEndpointsOutsideIsKept() {
        // Neither vertex is inside the box; only the drawn line between them is. A test that
        // asked "is any point in the viewport" would drop this.
        let route = [coordinate(37.45, -122.40), coordinate(37.45, -121.80)]
        #expect(RouteGeometry.polyline(route, intersects: viewport))
    }

    // MARK: - What a bounding-box test would get wrong

    @Test("a loop the viewport sits inside is dropped, though its box contains the viewport")
    func viewportInsideALoopIsDropped() {
        // A big rectangular loop well outside the viewport on every side. Its bounding box
        // holds the viewport whole, so a box test keeps it and the rider sees a row for a route
        // with nothing on screen.
        let loop = [
            coordinate(37.00, -123.00), coordinate(38.00, -123.00),
            coordinate(38.00, -121.00), coordinate(37.00, -121.00),
            coordinate(37.00, -123.00)
        ]
        let box = RouteGeometry.boundingBox(loop)
        #expect(box.contains(viewport), "fixture is only meaningful if the box does contain it")
        #expect(!RouteGeometry.polyline(loop, intersects: viewport))
    }

    @Test("a diagonal route is dropped when the viewport sits in an empty corner of its box")
    func viewportInAnEmptyCornerIsDropped() {
        let diagonal = [coordinate(37.00, -123.00), coordinate(38.00, -121.00)]
        let corner = RouteBounds(minLatitude: 37.90, maxLatitude: 38.00,
                                 minLongitude: -123.00, maxLongitude: -122.90)
        #expect(RouteGeometry.boundingBox(diagonal).intersects(corner))
        #expect(!RouteGeometry.polyline(diagonal, intersects: corner))
    }

    // MARK: - The clip is per segment, not per route

    @Test("a route whose first segment is outside is still kept when a later one crosses")
    func polylineWhoseFirstSegmentIsOutside() {
        // The regression that a fully-inside fixture cannot catch: with the slab clip inlined
        // into the polyline loop, its early exit abandons the whole route on this first
        // segment, and every zoomed-in view silently matches nothing.
        let route = [
            coordinate(37.00, -123.00),   // outside
            coordinate(37.00, -122.50),   // outside — this leg never approaches the viewport
            coordinate(37.45, -122.05)    // inside
        ]
        #expect(!RouteGeometry.segment(from: route[0], to: route[1], intersects: viewport))
        #expect(RouteGeometry.polyline(route, intersects: viewport))
    }

    // MARK: - Degenerates

    @Test("an empty polyline matches nothing")
    func emptyPolylineMatchesNothing() {
        #expect(!RouteGeometry.polyline([], intersects: viewport))
    }

    @Test("a one-point route is tested as a point")
    func singleCoordinatePolyline() {
        // `GPXRouteImporter` rejects only *no* coordinates, so a one-point GPX imports fine and
        // has no segments to walk. Without its own branch it could never match anything while
        // its marker sat in the middle of the viewport.
        #expect(RouteGeometry.polyline([coordinate(37.45, -122.05)], intersects: viewport))
        #expect(!RouteGeometry.polyline([coordinate(38.45, -122.05)], intersects: viewport))
    }

    @Test("a zero-length segment reduces to point-in-box")
    func zeroLengthSegment() {
        // `GPXRouteImporter` does not dedupe consecutive identical points, so these do arrive.
        let inside = coordinate(37.45, -122.05)
        let outside = coordinate(38.45, -122.05)
        #expect(RouteGeometry.segment(from: inside, to: inside, intersects: viewport))
        #expect(!RouteGeometry.segment(from: outside, to: outside, intersects: viewport))
    }

    @Test("a segment running along the viewport edge is kept")
    func segmentAlongTheEdge() {
        let along = [coordinate(37.40, -122.30), coordinate(37.40, -121.80)]
        #expect(RouteGeometry.polyline(along, intersects: viewport))
    }

    @Test("a segment parallel to an edge but outside it is dropped")
    func segmentParallelAndOutside() {
        let outside = [coordinate(37.30, -122.30), coordinate(37.30, -121.80)]
        #expect(!RouteGeometry.polyline(outside, intersects: viewport))
    }
}
