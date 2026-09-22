import Foundation
import Testing
@testable import Cyclometer

@Suite("RouteTerrain")
struct RouteTerrainTests {

    /// A straight route north with a point every 10 m, its elevation given by `profile` as a
    /// function of distance along it. Built in metres so each grade reads directly off the test.
    private func route(meters: Double, profile: (Double) -> Double) -> [RouteCoordinate] {
        let path = RouteFixtures.path(legs: [(0, meters)], spacingMeters: 10)
        let cumulative = RouteGeometry.cumulativeDistances(path)
        return zip(path, cumulative).map { point, distance in
            var point = point
            point.elevationMeters = profile(distance)
            return point
        }
    }

    /// Flat at `base`, then each `(length, grade)` in turn, then flat again for `tail` metres.
    private func profile(base: Double = 100, lead: Double = 1_000,
                         _ pitches: [(meters: Double, gradePercent: Double)],
                         tail: Double = 1_000) -> (total: Double, profile: (Double) -> Double) {
        let total = lead + pitches.reduce(0) { $0 + $1.meters } + tail
        return (total, { distance in
            var elevation = base
            var start = lead
            for pitch in pitches {
                let covered = min(max(distance - start, 0), pitch.meters)
                elevation += covered * pitch.gradePercent / 100
                start += pitch.meters
            }
            return elevation
        })
    }

    private func analyze(_ pitches: [(meters: Double, gradePercent: Double)], base: Double = 100) throws -> RouteTerrainAnalysis {
        let (total, elevation) = profile(base: base, pitches)
        return try #require(RouteTerrain.analyze(route(meters: total, profile: elevation)))
    }

    // MARK: - Nil and flat

    @Test("a route with no elevation has no analysis, under the same rule as gain and loss")
    func noElevationIsNil() {
        let path = RouteFixtures.path(legs: [(0, 2_000)], spacingMeters: 10)
        #expect(RouteTerrain.analyze(path) == nil)
        #expect(RouteGeometry.elevationGainLoss(path) == nil)
    }

    @Test("a level route is flat, with no climbs")
    func levelRouteIsFlat() throws {
        let terrain = try #require(RouteTerrain.analyze(route(meters: 20_000) { _ in 100 }))
        #expect(terrain.character == .flat)
        #expect(terrain.climbs.isEmpty)
        #expect(terrain.maxGradePercent == 0)
    }

    // MARK: - Climbs

    @Test("5 km at 6% is one Cat 3 climb of the right length, gain and grade")
    func steadyClimbIsCategorized() throws {
        let terrain = try analyze([(5_000, 6)])
        #expect(terrain.climbs.count == 1)
        let climb = try #require(terrain.climbs.first)
        // Score 5,000 × 6 = 30,000: above Cat 3's 16,000, below Cat 2's 32,000.
        #expect(climb.category == .cat3)
        // Smoothing rounds the corners by half a window either end, and no more.
        #expect(abs(climb.lengthMeters - 5_000) <= RouteTerrain.smoothingWindowMeters)
        // Each end is trimmed to where the road starts rising, costing at most the trim in gain.
        #expect(abs(climb.gainMeters - 300) <= 2 * RouteTerrain.climbEndTrimMeters)
        #expect(abs(climb.averageGradePercent - 6) < 0.1)
        #expect(abs(climb.startMeters - 1_000) <= RouteTerrain.smoothingWindowMeters)
        #expect(abs(climb.maxGradePercent - 6) < 0.1)
        #expect(abs(terrain.maxGradePercent - 6) < 0.1)
    }

    @Test("a dip shallower than the tolerance leaves one climb; a deeper one makes two")
    func dipToleranceDecidesWhereAClimbEnds() throws {
        // 3 km up, 100 m down, 3 km up. A 5 m dip is a false flat on the way up.
        let shallow = try analyze([(3_000, 6), (100, -5), (3_000, 6)])
        #expect(shallow.climbs.count == 1)
        #expect(shallow.climbs.first?.category == .cat2)

        // A 30 m descent is two climbs.
        let deep = try analyze([(3_000, 6), (300, -10), (3_000, 6)])
        #expect(deep.climbs.count == 2)
        #expect(deep.climbs.allSatisfy { $0.category == .cat3 })
    }

    @Test("a rise below Cat 4, too short or too shallow, is not listed")
    func smallRisesAreNotClimbs() throws {
        // 400 m at 10%: steep, but under the 500 m floor.
        #expect(try analyze([(400, 10)]).climbs.isEmpty)
        // 4 km at 2%: long, but under the 3% floor.
        #expect(try analyze([(4_000, 2)]).climbs.isEmpty)
        // 1 km at 5%: qualifies, but scores 5,000, under Cat 4's 8,000.
        #expect(try analyze([(1_000, 5)]).climbs.isEmpty)
    }

    @Test("categories follow the length × grade score at every threshold")
    func categoryThresholds() {
        #expect(ClimbCategory(score: 7_999) == nil)
        #expect(ClimbCategory(score: 8_000) == .cat4)
        #expect(ClimbCategory(score: 16_000) == .cat3)
        #expect(ClimbCategory(score: 32_000) == .cat2)
        #expect(ClimbCategory(score: 64_000) == .cat1)
        #expect(ClimbCategory(score: 80_000) == .hc)
        #expect(ClimbCategory.allCases.max() == .hc)
    }

    // MARK: - Grade smoothing

    @Test("one bad elevation point does not read as a wall")
    func spikeIsSmoothedAway() throws {
        // A 15 m spike on one point of a level road is 150% over the 10 m either side of it.
        let terrain = try #require(RouteTerrain.analyze(route(meters: 5_000) { abs($0 - 2_500) < 5 ? 115 : 100 }))
        #expect(terrain.maxGradePercent < 5)
        #expect(terrain.climbs.isEmpty)
        #expect(terrain.character == .flat)
    }

    // MARK: - FIETS

    @Test("FIETS matches the published figure for Alpe d'Huez")
    func fietsOnAKnownClimb() {
        // 13.8 km, 1,071 m gained, summit 1,850 m: 1071² / 138,000 + 0.85 = 9.16.
        let alpe = Climb(startMeters: 0, lengthMeters: 13_800, gainMeters: 1_071, averageGradePercent: 7.8,
                         maxGradePercent: 11, topElevationMeters: 1_850, category: .hc)
        #expect(abs(alpe.fiets - 9.16) < 0.01)
    }

    @Test("FIETS adds nothing for altitude below 1,000 m")
    func fietsAltitudeTermStartsAt1000() throws {
        let climb = try #require(try analyze([(5_000, 6)]).climbs.first)
        #expect(abs(climb.fiets - climb.gainMeters * climb.gainMeters / (climb.lengthMeters * 10)) < 1e-9)
    }

    @Test("the hardest climb is the one with the highest FIETS score")
    func hardestClimbByFiets() throws {
        let terrain = try analyze([(3_000, 5), (300, -10), (4_000, 7)])
        #expect(terrain.climbs.count == 2)
        #expect(terrain.hardestClimb == terrain.climbs.last)
    }

    // MARK: - Character

    @Test("character steps up with gain per kilometre")
    func characterThresholds() {
        func character(_ gain: Double) -> RouteCharacter {
            RouteTerrain.character(gainPerKilometer: gain, hardestCategory: nil, kicksPer10Kilometers: 0)
        }
        #expect(character(4.9) == .flat)
        #expect(character(RouteTerrain.rollingGainPerKilometer) == .rolling)
        #expect(character(RouteTerrain.hillyGainPerKilometer) == .hilly)
        #expect(character(RouteTerrain.mountainousGainPerKilometer) == .mountainous)
    }

    @Test("a Cat 1 or HC climb makes a route mountainous whatever its average")
    func bigClimbIsMountainous() {
        #expect(RouteTerrain.character(gainPerKilometer: 6, hardestCategory: .cat1, kicksPer10Kilometers: 0) == .mountainous)
        #expect(RouteTerrain.character(gainPerKilometer: 6, hardestCategory: .cat2, kicksPer10Kilometers: 0) == .rolling)
    }

    @Test("short steep kicks make a rolling route punchy, but never a flat one")
    func kicksMakeARoutePunchy() {
        #expect(RouteTerrain.character(gainPerKilometer: 7, hardestCategory: nil, kicksPer10Kilometers: 1) == .punchy)
        #expect(RouteTerrain.character(gainPerKilometer: 7, hardestCategory: nil, kicksPer10Kilometers: 0.9) == .rolling)
        #expect(RouteTerrain.character(gainPerKilometer: 4, hardestCategory: nil, kicksPer10Kilometers: 3) == .flat)
    }

    @Test("a route of repeated 300 m walls is punchy end to end")
    func repeatedWallsArePunchy() throws {
        // Four times: 300 m at 10% up, 300 m back down, 3.4 km level. Gain is at least 27 m a
        // wall — the 3 m hysteresis can leave the last metres of each unbanked — so 108 m or
        // more over 18 km is at least 6 m/km, rolling by gain, with two kicks every 10 km.
        let wall: [(meters: Double, gradePercent: Double)] = [(300, 10), (300, -10), (3_400, 0)]
        let terrain = try analyze(Array([wall, wall, wall, wall].joined()))
        #expect(terrain.climbs.isEmpty)
        #expect(terrain.character == .punchy)
    }

    @Test("a long HC climb makes the whole route mountainous")
    func hcRouteIsMountainous() throws {
        let terrain = try analyze([(15_000, 7)], base: 800)
        #expect(terrain.climbs.first?.category == .hc)
        #expect(terrain.character == .mountainous)
        // The summit is above 1,000 m, so the altitude term applies.
        let climb = try #require(terrain.climbs.first)
        #expect(climb.fiets > climb.gainMeters * climb.gainMeters / (climb.lengthMeters * 10))
    }
}
