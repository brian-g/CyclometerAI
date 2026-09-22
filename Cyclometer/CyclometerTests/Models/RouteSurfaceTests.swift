import Foundation
import Testing
@testable import Cyclometer

@Suite("RouteSurface")
struct RouteSurfaceTests {

    // MARK: - Classification

    @Test("OSM surface tags map to the four classes", arguments: [
        ("asphalt", SurfaceClass.paved), ("concrete", .paved), ("paving_stones", .paved), ("sett", .paved),
        ("gravel", .gravel), ("fine_gravel", .gravel), ("compacted", .gravel),
        ("dirt", .unpaved), ("ground", .unpaved), ("grass", .unpaved), ("unpaved", .unpaved),
        ("something_new", .unknown)
    ])
    func surfaceTags(tag: String, expected: SurfaceClass) {
        #expect(SurfaceClass(osmTags: ["highway": "residential", "surface": tag]) == expected)
    }

    @Test("a track with no surface falls back to its tracktype")
    func trackTypeFallback() {
        #expect(SurfaceClass(osmTags: ["highway": "track", "tracktype": "grade1"]) == .paved)
        #expect(SurfaceClass(osmTags: ["highway": "track", "tracktype": "grade2"]) == .gravel)
        #expect(SurfaceClass(osmTags: ["highway": "track", "tracktype": "grade4"]) == .unpaved)
        // The surface tag, when there is one, wins.
        #expect(SurfaceClass(osmTags: ["highway": "track", "tracktype": "grade4", "surface": "asphalt"]) == .paved)
    }

    @Test("a road with no surface tag is unknown, never assumed paved")
    func untaggedRoadIsUnknown() {
        #expect(SurfaceClass(osmTags: ["highway": "primary"]) == .unknown)
    }

    // MARK: - Dominant surface

    @Test("the dominant surface needs 60% of the known distance, else it is mixed")
    func dominantSurface() {
        #expect(RouteSurfaceBreakdown(pavedMeters: 700, gravelMeters: 300).dominant == .paved)
        #expect(RouteSurfaceBreakdown(pavedMeters: 500, gravelMeters: 500).dominant == .unknown)
        // Known distance is what the share is of, not the whole route.
        #expect(RouteSurfaceBreakdown(pavedMeters: 600, gravelMeters: 0, unknownMeters: 400).dominant == .paved)
    }

    @Test("under half the route tagged says nothing about its surface")
    func tooLittleKnownIsNil() {
        #expect(RouteSurfaceBreakdown(pavedMeters: 400, unknownMeters: 600).dominant == nil)
        #expect(RouteSurfaceBreakdown().dominant == nil)
    }

    // MARK: - Matching

    private let legs: [RouteFixtures.Leg] = [(0, 1_000)]

    /// A way running beside the route from `start` to `end` metres, `lateral` metres east of it.
    private func way(_ id: Int, from start: Double, to end: Double, lateral: Double, surface: String) -> OSMWay {
        OSMWay(id: id, tags: ["highway": "residential", "surface": surface], geometry: [
            RouteFixtures.point(along: legs, at: start, lateralMeters: lateral),
            RouteFixtures.point(along: legs, at: end, lateralMeters: lateral)
        ])
    }

    @Test("each stretch takes the surface of the nearest way within reach")
    func matchesNearestWay() {
        let route = RouteFixtures.path(legs: legs, spacingMeters: 10)
        let ways = [
            way(1, from: 0, to: 500, lateral: 5, surface: "asphalt"),
            way(2, from: 500, to: 1_000, lateral: 10, surface: "gravel"),
            // Alongside the whole route but 40 m off it: a parallel road, out of reach.
            way(3, from: 0, to: 1_000, lateral: 40, surface: "dirt")
        ]
        let breakdown = RouteSurface.breakdown(route: route, ways: ways)

        let tolerance = RouteSurface.sampleSpacingMeters * 1.5
        #expect(abs(breakdown.pavedMeters - 500) <= tolerance)
        #expect(abs(breakdown.gravelMeters - 500) <= tolerance)
        #expect(breakdown.unpavedMeters == 0)
        #expect(abs(breakdown.totalMeters - RouteGeometry.distanceMeters(route)) < 1e-6)
    }

    @Test("where two ways are in reach, the nearer one wins")
    func nearerWayWins() {
        let route = RouteFixtures.path(legs: legs, spacingMeters: 10)
        let ways = [
            way(1, from: 0, to: 1_000, lateral: 15, surface: "gravel"),
            way(2, from: 0, to: 1_000, lateral: -3, surface: "asphalt")
        ]
        #expect(RouteSurface.breakdown(route: route, ways: ways).dominant == .paved)
        #expect(RouteSurface.breakdown(route: route, ways: ways).gravelMeters == 0)
    }

    @Test("a stretch with no way in reach is unknown")
    func noWayIsUnknown() {
        let route = RouteFixtures.path(legs: legs, spacingMeters: 10)
        let breakdown = RouteSurface.breakdown(route: route, ways: [])
        #expect(breakdown.unknownMeters == breakdown.totalMeters)
        #expect(breakdown.totalMeters > 0)
    }

    @Test("point-to-segment distance is perpendicular inside the segment and to the end beyond it")
    func pointToSegmentDistance() {
        let start = RouteFixtures.origin
        let end = RouteFixtures.offset(start, bearingDegrees: 0, meters: 100)
        let beside = RouteFixtures.offset(RouteFixtures.offset(start, bearingDegrees: 0, meters: 50), bearingDegrees: 90, meters: 12)
        let beyond = RouteFixtures.offset(end, bearingDegrees: 0, meters: 30)
        #expect(abs(RouteSurface.distance(from: beside, toSegment: start, end) - 12) < 0.01)
        #expect(abs(RouteSurface.distance(from: beyond, toSegment: start, end) - 30) < 0.01)
    }
}

@Suite("OverpassClient")
struct OverpassClientTests {

    @Test("a long route is split into requests that share their boundary points")
    func chunking() throws {
        let route = RouteFixtures.path(legs: [(0, 50_000)], spacingMeters: 100)
        let chunks = OverpassClient.chunks(route)

        // 50 km at 50 m is about 1,000 samples plus the finish, 400 intervals to a request.
        let points = RouteGeometry.resampled(route, everyMeters: OverpassClient.querySpacingMeters).count + 1
        #expect(chunks.count == Int((Double(points - 1) / Double(OverpassClient.pointsPerQuery)).rounded(.up)))
        #expect(chunks.count == 3)
        #expect(chunks.dropLast().allSatisfy { $0.count == OverpassClient.pointsPerQuery + 1 })
        for (previous, next) in zip(chunks, chunks.dropFirst()) {
            #expect(previous.last == next.first)
        }
        #expect(chunks.first?.first == RouteGeometry.resampled(route, everyMeters: 50).first?.coordinate)
        #expect(chunks.last?.last == route.last)
    }

    @Test("the query asks for highways around the route's line at the match radius")
    func queryShape() {
        let chunk = [
            RouteCoordinate(latitude: 36.123456, longitude: -80.5),
            RouteCoordinate(latitude: 36.2, longitude: -80.654321)
        ]
        #expect(OverpassClient.query(chunk)
                == "[out:json][timeout:25];way(around:20,36.12346,-80.50000,36.20000,-80.65432)[\"highway\"];out tags geom;")
    }

    @Test("the response decodes ways and skips anything without a usable line")
    func decoding() throws {
        let json = """
        {"elements": [
          {"type": "way", "id": 1, "tags": {"highway": "residential", "surface": "asphalt"},
           "geometry": [{"lat": 36.0, "lon": -80.0}, {"lat": 36.001, "lon": -80.0}]},
          {"type": "way", "id": 2, "geometry": [{"lat": 36.0, "lon": -80.0}]},
          {"type": "node", "id": 3, "lat": 36.0, "lon": -80.0},
          {"type": "way", "id": 4, "geometry": [{"lat": 36.0, "lon": -80.0}, null, {"lat": 36.002, "lon": -80.0}]}
        ]}
        """
        let ways = try OverpassClient.decode(Data(json.utf8))
        #expect(ways.map(\.id) == [1, 4])
        #expect(ways.first?.tags["surface"] == "asphalt")
        #expect(ways.last?.tags == [:])
        #expect(ways.last?.geometry.count == 2)
    }
}
