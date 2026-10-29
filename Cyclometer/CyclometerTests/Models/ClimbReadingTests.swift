import Foundation
import Testing
@testable import Cyclometer

/// #463 — W22's climb at the rider's progress, on a route `RouteTerrain.analyze` found the climbs on.
@Suite("ClimbReading")
struct ClimbReadingTests {

    /// 7 km north, a point every 10 m: level at 100 m to 1 km, 2 km up at 8%, 1 km down at 4%,
    /// 2 km up at 5%, then level. The descent keeps the two climbs apart.
    private func route() throws -> (route: NavigationRoute, terrain: RouteTerrainAnalysis) {
        let coordinates = RouteFixtures.withElevation(
            RouteFixtures.path(legs: [(0, 7_000)], spacingMeters: 10), Self.elevation(atMeters:)
        )
        let terrain = try #require(RouteTerrain.analyze(coordinates))
        let route = try #require(NavigationRoute(coordinates: coordinates, maneuvers: [], terrain: terrain))
        return (route, terrain)
    }

    private static func elevation(atMeters d: Double) -> Double {
        let pitches: [(start: Double, end: Double, grade: Double)] = [(1_000, 3_000, 8), (3_000, 4_000, -4), (4_000, 6_000, 5)]
        return pitches.reduce(100) { elevation, pitch in
            elevation + (min(max(d, pitch.start), pitch.end) - pitch.start) * pitch.grade / 100
        }
    }

    /// The issue's check: `Climb.startMeters` is measured on the 10 m resample, the ride on
    /// `cumulativeDistances`. Both are distance along the same polyline, so a climb's top lands on
    /// the route's own elevation there.
    @Test("The ride's climbs are the analysis's, on the ride's own distances")
    func climbsLineUpWithTheRoute() throws {
        let (route, terrain) = try route()
        try #require(route.climbs.count == 2)
        #expect(route.climbs.map(\.climb) == terrain.climbs)
        #expect(abs(route.climbs[0].startMeters - 1_000) < 60)
        #expect(abs(route.climbs[0].topMeters - 3_000) < 60)
        #expect(abs(route.climbs[1].startMeters - 4_000) < 60)
        #expect(abs(route.climbs[1].topMeters - 6_000) < 60)
        for climb in route.climbs {
            #expect(climb.elevation(atMeters: climb.topMeters) == climb.climb.topElevationMeters)
            #expect(abs(climb.elevation(atMeters: climb.startMeters) + climb.climb.gainMeters
                - climb.climb.topElevationMeters) < 1e-9)
            // The road's own elevation at the climb's top, as far along as the ride measures it.
            #expect(abs(Self.elevation(atMeters: climb.topMeters) - climb.climb.topElevationMeters) < 2)
        }
    }

    @Test("Before the first climb, it is next")
    func beforeTheFirstClimb() throws {
        let climbs = try route().route.climbs
        #expect(ClimbReading.at(progressMeters: 0, climbs: climbs) == .next(climbs[0], metersToStart: climbs[0].startMeters))
    }

    @Test("At a climb's start, all of it is left")
    func atAClimbsStart() throws {
        let climb = try route().route.climbs[0]
        #expect(ClimbReading.at(progressMeters: climb.startMeters, climbs: [climb]) == .climbing(
            climb, metersToTop: climb.climb.lengthMeters, metersToClimb: climb.climb.gainMeters, fraction: 0
        ))
    }

    /// Issue AC: distance and climbing left fall as the rider climbs, and reach 0 at the top.
    @Test("Up a climb, distance and climbing left fall to 0 at the top")
    func climbingLeftFallsToZero() throws {
        let climb = try route().route.climbs[0]
        var last = (top: Double.infinity, climb: Double.infinity)
        for progress in stride(from: climb.startMeters, through: climb.topMeters, by: 10) {
            guard case .climbing(_, let toTop, let toClimb, _) = ClimbReading.at(progressMeters: progress, climbs: [climb])
            else { Issue.record("not on the climb at \(progress) m"); return }
            #expect(toTop <= last.top && toClimb <= last.climb, "at \(progress) m")
            last = (toTop, toClimb)
        }
        #expect(ClimbReading.at(progressMeters: climb.topMeters, climbs: [climb])
            == .climbing(climb, metersToTop: 0, metersToClimb: 0, fraction: 1))
    }

    @Test("Between climbs, the next one is ahead")
    func betweenClimbs() throws {
        let climbs = try route().route.climbs
        let progress = climbs[0].topMeters + 1
        #expect(ClimbReading.at(progressMeters: progress, climbs: climbs)
            == .next(climbs[1], metersToStart: climbs[1].startMeters - progress))
    }

    @Test("After the last climb, there is none ahead")
    func afterTheLastClimb() throws {
        let climbs = try route().route.climbs
        #expect(ClimbReading.at(progressMeters: climbs[1].topMeters + 1, climbs: climbs) == .noClimbAhead)
        #expect(ClimbReading.at(progressMeters: 0, climbs: []) == .noClimbAhead)
    }

    /// A loop's wrap takes progress back to the lap's start: the first climb is ahead again. The
    /// wrap itself is driven in `NavigationFeatureTests`.
    @Test("On a loop's second lap, the first climb is next again")
    func secondLapOfALoop() throws {
        let climbs = try route().route.climbs
        #expect(ClimbReading.at(progressMeters: 6_900, climbs: climbs) == .noClimbAhead)
        #expect(ClimbReading.at(progressMeters: 100, climbs: climbs) == .next(climbs[0], metersToStart: climbs[0].startMeters - 100))
    }

    /// A stored analysis of some other polyline doesn't place a climb off the route.
    @Test("A climb past the profile's end is dropped")
    func aClimbOffTheProfileIsDropped() {
        let climb = Climb(
            startMeters: 900, lengthMeters: 500, gainMeters: 40, averageGradePercent: 8, maxGradePercent: 9,
            topElevationMeters: 140, category: .cat4
        )
        #expect(RouteClimb(climb, smoothed: Array(repeating: 100, count: 101), spacing: 10) == nil)
    }
}
