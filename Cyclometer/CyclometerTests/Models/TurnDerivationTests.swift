import Foundation
import Testing
@testable import Cyclometer

@Suite("TurnDerivation")
struct TurnDerivationTests {

    // MARK: - Fixtures
    //
    // Built in metres rather than as literal coordinates. At 36°N one ten-thousandth of a
    // degree is 11.06 m of latitude but 8.95 m of longitude, so "turn 90 degrees right" is
    // not something a hand-written lat/lon pair says legibly. Walking a path by bearing and
    // distance inverts the tangent-plane arithmetic the code under test uses, which makes
    // the fixture an independent second route to the same geometry.

    private static let origin = RouteCoordinate(latitude: 36.0, longitude: -80.0, elevationMeters: nil)

    private func path(
        from start: RouteCoordinate = TurnDerivationTests.origin,
        legs: [(bearingDegrees: Double, meters: Double)],
        spacingMeters: Double = 5
    ) -> [RouteCoordinate] {
        var points = [start]
        var latitude = start.latitude
        var longitude = start.longitude
        for leg in legs {
            let steps = max(1, Int((leg.meters / spacingMeters).rounded()))
            let step = leg.meters / Double(steps)
            for _ in 0..<steps {
                let meanLatitude = latitude * .pi / 180
                let sinLatitude = sin(meanLatitude)
                let w = 1 - 0.006_694_379_990_141_316 * sinLatitude * sinLatitude
                let meridional = 6_378_137.0 * (1 - 0.006_694_379_990_141_316) / (w * w.squareRoot())
                let normal = 6_378_137.0 / w.squareRoot()
                latitude += (step * cos(leg.bearingDegrees * .pi / 180) / meridional) * 180 / .pi
                longitude += (step * sin(leg.bearingDegrees * .pi / 180) / (normal * cos(meanLatitude))) * 180 / .pi
                points.append(RouteCoordinate(latitude: latitude, longitude: longitude, elevationMeters: nil))
            }
        }
        return points
    }

    /// A constant-radius turn, so "90 degrees drawn with a 30 m corner radius" is expressible.
    ///
    /// This is the fixture the first design of `TurnDerivation` did not have, and not having
    /// it is exactly why its defect survived review: every geometry test used a single sharp
    /// vertex, and a sharp vertex is the one case where measuring curvature over a window and
    /// measuring the turn angle give the same answer.
    private func arc(
        startBearing: Double,
        sweepDegrees: Double,
        radiusMeters: Double,
        stepMeters: Double = 2
    ) -> [(bearingDegrees: Double, meters: Double)] {
        let length = abs(sweepDegrees * .pi / 180) * radiusMeters
        let steps = max(2, Int(length / stepMeters))
        return (0..<steps).map {
            (
                bearingDegrees: startBearing + sweepDegrees * (Double($0) + 0.5) / Double(steps),
                meters: length / Double(steps)
            )
        }
    }

    private func corner(radiusMeters: Double, sweepDegrees: Double = 90) -> [RouteCoordinate] {
        path(
            legs: [(0, 80)] + arc(startBearing: 0, sweepDegrees: sweepDegrees, radiusMeters: radiusMeters)
                + [(sweepDegrees, 80)],
            spacingMeters: 2
        )
    }

    private func cue(
        _ coordinate: RouteCoordinate,
        name: String? = nil,
        type: String? = nil,
        description: String? = nil
    ) -> RouteCuePoint {
        RouteCuePoint(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            name: name,
            cueDescription: description,
            type: type
        )
    }

    private func maneuvers(_ coordinates: [RouteCoordinate], _ cues: [RouteCuePoint] = []) -> [Maneuver] {
        TurnDerivation.maneuvers(coordinates: coordinates, cuePoints: cues)
    }

    // MARK: - Acceptance: a right-angle grid

    @Test("a right-angle grid yields one maneuver per corner, with the correct side")
    func rightAngleGridYieldsOneManeuverPerCorner() {
        let right = maneuvers(path(legs: [(0, 100), (90, 100), (180, 100)]))
        #expect(right.count == 2)
        #expect(right.allSatisfy { $0.direction == .right })

        let left = maneuvers(path(legs: [(0, 100), (270, 100), (180, 100)]))
        #expect(left.count == 2)
        #expect(left.allSatisfy { $0.direction == .left })
    }

    @Test("each corner is reported near its own along-route distance")
    func cornersAreReportedWhereTheyAre() throws {
        let found = maneuvers(path(legs: [(0, 100), (90, 100), (180, 100)]))
        try #require(found.count == 2)
        #expect(abs(found[0].distanceAlongRouteMeters - 100) <= TurnDerivation.resampleStepMeters)
        #expect(abs(found[1].distanceAlongRouteMeters - 200) <= TurnDerivation.resampleStepMeters)
    }

    // MARK: - Acceptance: a smooth curve

    @Test("a sweeping bend emits nothing however far it eventually turns")
    func aSweepingBendIsNotAManeuver() {
        // 90 degrees, but spread over 300 m of road: the rider follows the road round.
        #expect(maneuvers(corner(radiusMeters: 200)).isEmpty)
        #expect(maneuvers(corner(radiusMeters: 120)).isEmpty)
    }

    // MARK: - Acceptance: switchbacks and close corners

    @Test("a switchback emits distinct maneuvers rather than one merged turn")
    func switchbackEmitsDistinctManeuvers() throws {
        let found = maneuvers(path(legs: [(0, 80), (180, 60), (0, 80)]))
        try #require(found.count == 2)
        #expect(found.allSatisfy { $0.direction == .uTurn })
        #expect(found[1].distanceAlongRouteMeters - found[0].distanceAlongRouteMeters
            >= TurnDerivation.minimumSeparationMeters)
    }

    @Test("two corners closer than the separation minimum emit one maneuver")
    func closeCornersCollapseToOne() {
        #expect(maneuvers(path(legs: [(0, 80), (270, 15), (0, 80)])).count == 1)
    }

    @Test("the survivor of a collapse is the sharper turn, not the first one reached")
    func theSharperTurnSurvivesACollapse() throws {
        // A 40-degree jog, then a hard left 15 m later. Announcing the jog and swallowing
        // the hard left would send the rider straight through the turn they had to make.
        let found = maneuvers(path(legs: [(0, 80), (40, 15), (-50, 80)]))
        try #require(found.count == 1)
        #expect(found[0].direction == .left)
    }

    // MARK: - Acceptance: cues beat geometry

    @Test("a cue whose name disagrees with the geometry resolves in favour of the cue")
    func cueNameBeatsGeometry() throws {
        let route = path(legs: [(0, 100), (90, 100)])
        let geometric = maneuvers(route)
        try #require(geometric.first?.direction == .right)

        let cued = maneuvers(route, [cue(route[route.count / 2], name: "Turn left onto County Road S")])
        try #require(cued.count == 1)
        #expect(cued[0].direction == .left)
        #expect(cued[0].name == "Turn left onto County Road S")
    }

    @Test("a file with no cues still produces maneuvers via the geometry path")
    func bareTrackStillNavigates() {
        #expect(!maneuvers(path(legs: [(0, 100), (90, 100)])).isEmpty)
    }

    // MARK: - Boundaries, from both sides

    @Test("the turn threshold is inclusive at its boundary and excludes just below it")
    func turnThresholdBoundary() {
        let threshold = TurnDerivation.turnThresholdDegrees
        #expect(TurnDerivation.direction(forTotalDegrees: threshold) == .right)
        #expect(TurnDerivation.direction(forTotalDegrees: -threshold) == .left)
        #expect(TurnDerivation.direction(forTotalDegrees: threshold - 0.1) == nil)
        #expect(TurnDerivation.direction(forTotalDegrees: -(threshold - 0.1)) == nil)
    }

    @Test("the u-turn threshold is inclusive at its boundary")
    func uTurnThresholdBoundary() {
        let threshold = TurnDerivation.uTurnThresholdDegrees
        #expect(TurnDerivation.direction(forTotalDegrees: threshold) == .uTurn)
        #expect(TurnDerivation.direction(forTotalDegrees: -threshold) == .uTurn)
        #expect(TurnDerivation.direction(forTotalDegrees: threshold - 0.1) == .right)
        #expect(TurnDerivation.direction(forTotalDegrees: -(threshold - 0.1)) == .left)
    }

    @Test("corners either side of the separation minimum collapse and do not")
    func separationBoundary() {
        let separation = TurnDerivation.minimumSeparationMeters
        #expect(maneuvers(path(legs: [(0, 80), (90, separation + 15), (0, 80)], spacingMeters: 2)).count == 2)
        #expect(maneuvers(path(legs: [(0, 80), (90, separation - 15), (0, 80)], spacingMeters: 2)).count == 1)
    }

    @Test("a corner sharper than the radius gate is a maneuver; a gentler one is road")
    func turnRadiusBoundary() {
        let radius = TurnDerivation.maximumTurnRadiusMeters
        #expect(!maneuvers(corner(radiusMeters: radius / 2)).isEmpty)
        #expect(maneuvers(corner(radiusMeters: radius * 3)).isEmpty)
    }

    // MARK: - The properties the first design lacked

    @Test("the same corner is found however densely the file samples it", arguments: [
        0.5, 1.0, 2.0, 5.0, 10.0, 25.0, 50.0, 100.0,
    ])
    func detectionIsIndependentOfSamplingDensity(spacing: Double) throws {
        let found = maneuvers(path(legs: [(0, 200), (90, 200)], spacingMeters: spacing))
        try #require(found.count == 1, "spacing \(spacing) m produced \(found.count) maneuvers")
        #expect(found[0].direction == .right)
    }

    @Test("two corners 200 m apart stay two on a decimated file", arguments: [5.0, 50.0, 100.0, 150.0, 200.0])
    func adjacentCornersDoNotMergeOnACoarseFile(spacing: Double) {
        // The first design grouped candidates by array index, so on a file thinned to
        // 150-200 m these two corners landed on consecutive indices and became one maneuver.
        let found = maneuvers(path(legs: [(0, 200), (90, 200), (180, 200)], spacingMeters: spacing))
        #expect(found.count == 2, "spacing \(spacing) m produced \(found.count) maneuvers")
    }

    @Test("a 90-degree corner is found whatever radius it was drawn with", arguments: [
        5.0, 10.0, 20.0, 30.0, 40.0,
    ])
    func detectionIsIndependentOfDrawnCornerRadius(radius: Double) throws {
        // The defect that sank the first design: it measured curvature over a fixed window,
        // so the same corner read 85 degrees at a 5 m radius and vanished entirely past 30 m.
        let found = maneuvers(corner(radiusMeters: radius))
        try #require(found.count == 1, "radius \(radius) m produced \(found.count) maneuvers")
        #expect(found[0].direction == .right)
    }

    @Test("a switchback reads as a u-turn at every realistic radius", arguments: [4.0, 8.0, 12.0, 20.0])
    func hairpinsClassifyAsUTurns(radius: Double) throws {
        let found = maneuvers(corner(radiusMeters: radius, sweepDegrees: 180))
        try #require(found.count == 1, "radius \(radius) m produced \(found.count) maneuvers")
        #expect(found[0].direction == .uTurn)
    }

    // MARK: - Cue reading

    @Test("the instruction is read, not the street it names")
    func streetNamesDoNotOverrideTheInstruction() {
        // "Turn left onto Rightmire Road" contains "right"; word boundaries alone do not help.
        #expect(TurnDerivation.reading(ofText: "Turn left onto Rightmire Road") == .direction(.left))
        #expect(TurnDerivation.reading(ofText: "Turn right onto Leftwich Lane") == .direction(.right))
        #expect(TurnDerivation.reading(ofText: "Turn left onto Right Fork Rd") == .direction(.left))
    }

    @Test("cue wording maps to a direction", arguments: [
        ("Left", TurnDerivation.CueReading.direction(.left)),
        ("Right", .direction(.right)),
        ("Turn left onto County Road S", .direction(.left)),
        ("Slight right", .direction(.slightRight)),
        ("Bear left", .direction(.slightLeft)),
        ("Keep right", .direction(.slightRight)),
        ("Sharp left", .direction(.left)),
        ("U-turn", .direction(.uTurn)),
        ("U turn", .direction(.uTurn)),
        ("Summit", .notATurn),
        ("Water", .notATurn),
        ("Food", .notATurn),
        ("Start", .notATurn),
        ("Continue straight", .notATurn),
        ("Cafe stop", .unstated),
    ])
    func cueWordingIsRead(text: String, expected: TurnDerivation.CueReading) {
        #expect(TurnDerivation.reading(ofText: text) == expected)
    }

    @Test("type is read before name, and name before description")
    func cueFieldsAreReadInPriorityOrder() {
        #expect(TurnDerivation.reading(of: cue(Self.origin, name: "Turn right", type: "Left"))
            == .direction(.left))
        #expect(TurnDerivation.reading(of: cue(Self.origin, name: "Turn right", description: "Turn left"))
            == .direction(.right))
        #expect(TurnDerivation.reading(of: cue(Self.origin, description: "Turn left"))
            == .direction(.left))
    }

    // MARK: - Cue path behaviour

    @Test("cues are ordered by along-route distance, not by the order the importer built them")
    func cuesAreSortedAlongTheRoute() throws {
        // GPXRouteImporter emits every <wpt> and then every named <rtept>, so a late waypoint
        // routinely arrives before an early route point.
        let route = path(legs: [(0, 100), (90, 100), (180, 100)])
        let late = route[route.count - 4]
        let early = route[4]
        let found = maneuvers(route, [
            cue(late, name: "Turn right onto Last St"),
            cue(early, name: "Turn left onto First St"),
        ])
        try #require(found.count == 2)
        #expect(found[0].name == "Turn left onto First St")
        #expect(found[1].name == "Turn right onto Last St")
        #expect(found[0].distanceAlongRouteMeters < found[1].distanceAlongRouteMeters)
    }

    @Test("a point of interest with no direction and straight road is not a maneuver")
    func poiCuesAreDropped() {
        let route = path(legs: [(0, 200)])
        #expect(maneuvers(route, [cue(route[10], name: "Water stop")]).isEmpty)
        #expect(maneuvers(route, [cue(route[10], name: "Cafe")]).isEmpty)
    }

    @Test("a lone unusable cue does not suppress the geometry path")
    func aStartOnlyCueFileStillNavigates() {
        // Garmin Connect and Strava both export a route whose only <wpt> is named "Start".
        // Keying exclusivity off the presence of a cue rather than off one resolving would
        // ship this route with no maneuvers at all.
        let route = path(legs: [(0, 100), (90, 100)])
        #expect(!maneuvers(route, [cue(route[0], name: "Start", type: "Start")]).isEmpty)
    }

    @Test("a cue far off the route is not snapped onto it")
    func distantCuesAreRejected() {
        let route = path(legs: [(0, 200)])
        let faraway = path(from: Self.origin, legs: [(90, 2_000)]).last!
        #expect(maneuvers(route, [cue(faraway, name: "Turn left")]).isEmpty)
    }

    @Test("a turn cued twice becomes one maneuver")
    func duplicateCuesCollapse() {
        // A file carrying both <trk>+<wpt> and a named <rte> cues the same corner twice, and
        // the importer keeps both by design.
        let route = path(legs: [(0, 100), (90, 100)])
        let corner = route[route.count / 2]
        let found = maneuvers(route, [
            cue(corner, name: "Turn right onto Elm"),
            cue(corner, name: "Turn right onto Elm", type: "Right"),
        ])
        #expect(found.count == 1)
    }

    @Test("a cue that states no direction takes it from the polyline")
    func unstatedCuesFallBackToGeometry() throws {
        let route = path(legs: [(0, 100), (270, 100)])
        let found = maneuvers(route, [cue(route[route.count / 2], name: "Junction")])
        try #require(found.count == 1)
        #expect(found[0].direction == .left)
    }

    // MARK: - Degenerate input

    @Test("routes too short or too degenerate to have a turn produce none")
    func degenerateRoutesProduceNoManeuvers() {
        let point = Self.origin
        #expect(maneuvers([]).isEmpty)
        #expect(maneuvers([point]).isEmpty)
        #expect(maneuvers([point, point]).isEmpty)
        #expect(maneuvers(Array(repeating: point, count: 50)).isEmpty)
    }

    @Test("duplicated consecutive points do not invent or lose a turn")
    func duplicatePointsAreSteppedOver() {
        // GPXRouteImporter drops non-finite and out-of-range points but never de-duplicates,
        // so a zero-length segment — which has no defined bearing — does reach this code.
        let route = path(legs: [(0, 100), (90, 100)])
        let duplicated = route.flatMap { [$0, $0] }
        #expect(maneuvers(duplicated).count == 1)
        #expect(maneuvers(duplicated).first?.direction == .right)
    }

    @Test("a closed loop does not emit a maneuver at the point where it joins up")
    func closedLoopsDoNotWrap() {
        // Four corners, but the rider starts and finishes on the fourth: a route's start is
        // not a turn, and nothing here wraps around the seam.
        #expect(maneuvers(path(legs: [(0, 100), (90, 100), (180, 100), (270, 100)])).count == 3)
    }

    @Test("a straight route has no turns however it is oriented", arguments: [0.0, 45.0, 90.0, 180.0, 225.0])
    func straightRoutesHaveNoTurns(bearing: Double) {
        // The windowed design read the very first sample against an undefined inbound bearing
        // of due north, so any route not setting off northward opened with a phantom turn.
        #expect(maneuvers(path(legs: [(bearing, 200)])).isEmpty)
    }

    // MARK: - Reproducibility

    @Test("the same route always derives the same maneuvers")
    func derivationIsDeterministic() {
        // The precedent is RouteGeometry.distanceMeters, where CLLocation returned two answers
        // for one polyline inside a single test process.
        let route = path(legs: [(0, 100), (90, 100), (180, 100)])
        let runs = Set((0..<50).map { _ in
            maneuvers(route).map { "\($0.direction)@\($0.distanceAlongRouteMeters)" }.joined(separator: ",")
        })
        #expect(runs.count == 1)
    }

    @Test("GPS scatter on a recorded track does not fragment the turn", arguments: [0.0, 1.0, 2.0, 3.0])
    func recordedTrackScatterDoesNotFragmentATurn(sigma: Double) throws {
        // A bare recorded track is what the geometry path actually gets — a file with cues
        // never reaches it. At 1 Hz a bike lays a fix every 5-10 m, and this repo already
        // discards fixes worse than GPSFixFilter.maxHorizontalAccuracy (10 m), so a couple of
        // metres of scatter on 7 m spacing is the realistic worst case. That is still 15-25
        // degrees of heading noise per sample, which fragmented one corner into seven turns
        // before the reversal hysteresis went in.
        let clean = path(
            legs: [(0, 80)] + arc(startBearing: 0, sweepDegrees: 90, radiusMeters: 10, stepMeters: 7)
                + [(90, 80)],
            spacingMeters: 7
        )
        let found = maneuvers(scattered(clean, sigmaMeters: sigma))
        try #require(found.count == 1, "sigma \(sigma) m produced \(found.count) maneuvers")
        #expect(found[0].direction == .right)
    }

    /// Deterministic pseudo-scatter. A test that fails one run in twenty is worse than no test,
    /// and `RouteGeometryTests` already treats reproducibility as the bar for this suite.
    private func scattered(_ coordinates: [RouteCoordinate], sigmaMeters: Double) -> [RouteCoordinate] {
        var seed = 20_260_908.0
        func noise() -> Double {
            seed = (seed * 1_103_515_245 + 12_345).truncatingRemainder(dividingBy: 2_147_483_648)
            return (seed / 2_147_483_648 - 0.5) * 2 * sigmaMeters
        }
        return coordinates.map {
            RouteCoordinate(
                latitude: $0.latitude + noise() / 111_320,
                longitude: $0.longitude + noise() / (111_320 * cos(36.0 * .pi / 180)),
                elevationMeters: nil
            )
        }
    }
}
