import Foundation

/// Turns a planned route into the list of maneuvers a rider needs to be told about.
///
/// OQ12 resolved MVP navigation to GPX import with no `MKDirections` (`PRD.md:486`), so
/// there is no routing engine to ask where the turns are — they have to come out of the
/// file. Two sources, in priority order: the cues the file states, and failing those, the
/// shape of the polyline itself.
///
/// Pure arithmetic with no persistence coupling, and run at route *load* rather than at
/// import: `RouteDetail` carries the polyline and the cues, nothing stores the output, and
/// a later fix to this file therefore cannot leave already-imported routes on stale
/// maneuvers (`Route.swift:189-192`).
///
/// # Why the turn is *accumulated* rather than measured
///
/// The obvious implementation — take the bearing 20 m before a point and 20 m after, and
/// call the difference the turn angle — was built first and is wrong. That difference is a
/// measure of *curvature over the window*, not of turn angle: the same 90° corner reads 85°
/// when the exporter drew it with a 5 m corner radius, 43° at 28 m, and nothing at all at
/// 30 m or wider, where it slips under the threshold entirely. Whether a real intersection
/// became a maneuver depended on which planning tool wrote the file.
///
/// Summing many small per-sample heading changes instead gives the true angle regardless of
/// how tightly the corner was drawn, and it separates cleanly into the two questions that
/// actually matter: *how far does the road turn* (the sum) and *over what distance* (the
/// span). A corner is a large turn over a short distance; a sweeping bend is the same turn
/// over a long one, and only the first is an event worth announcing.
enum TurnDerivation {

    // MARK: - Thresholds

    /// The polyline is re-sampled to this spacing before anything is measured.
    ///
    /// This is the constant that makes every other one meaningful. A GPX may carry a point
    /// every metre or every 200 m, and the first design compared array *indices* to decide
    /// whether two turns were close together — which merged two corners 200 m apart into one
    /// maneuver on a decimated file, because there index proximity is not road proximity.
    /// After resampling it is, and that whole class of bug is gone.
    ///
    /// 10 m rather than something finer because the samples are differenced: halving the
    /// step doubles the share of each heading change that is GPS noise rather than road.
    static let resampleStepMeters = 10.0

    /// Below this, the road is bending and the rider does not need telling.
    static let turnThresholdDegrees = 40.0

    /// At or above this, "left" and "right" stop describing what the rider has to do.
    static let uTurnThresholdDegrees = 135.0

    /// Two maneuvers closer together than this are one maneuver.
    ///
    /// Also the gap that ends a turn: once the road has run straight for this far, the next
    /// bend is a new turn rather than a continuation of the last one.
    static let minimumSeparationMeters = 25.0

    /// A turn spread more gently than this radius is road geometry, not a maneuver.
    ///
    /// The companion to `turnThresholdDegrees`, and the reason the angle no longer has to
    /// do two jobs at once: the sum says *how far* the road turns, this says whether it
    /// turns *sharply enough to be an event*. A 90° change over 300 m of sweeping road is
    /// not a turn; the same 90° over 40 m is. 60 m is about where a rider stops steering
    /// for a corner and simply follows the road round.
    static let maximumTurnRadiusMeters = 60.0

    /// A heading change smaller than this does not start or end a turn.
    ///
    /// Deliberately *not* a floor on what counts toward the total — sub-threshold changes
    /// inside an open turn still accumulate, or a long climb taken in half-degree steps
    /// would never register. It exists so that floating-point dust on a dead-straight road
    /// cannot hold a turn open across it.
    ///
    /// Chosen just under `resampleStepMeters / maximumTurnRadiusMeters` in degrees (9.5°),
    /// so anything sharp enough for the radius gate to accept is comfortably sharp enough
    /// to open a turn in the first place.
    static let turningNoiseFloorDegrees = 3.0

    /// How far the road has to bend back the other way before that counts as a new turn.
    ///
    /// Hysteresis, for the same reason `RouteGeometry.elevationGainLoss` accumulates against
    /// a moving reference rather than filtering each delta: a bare recorded track is the input
    /// the geometry path actually gets, and at 1 Hz a bike lays down a fix every 5-10 m with
    /// a couple of metres of scatter — which is 15-30° of heading noise on every single
    /// sample. Ending a turn at the first sample that points the other way would shatter one
    /// corner into half a dozen sub-threshold fragments and report none of them.
    ///
    /// The counter-turn has to *accumulate* past this, and resets the moment the road resumes
    /// its original direction, so scatter about a left-hand bend never reaches it while a
    /// genuine right-hander crosses it almost immediately.
    static let reversalThresholdDegrees = 20.0

    /// A cue further than this from the polyline is not about the route.
    ///
    /// Komoot writes cafés and viewpoints as `<wpt>`s in the same file as the turn cues.
    /// Without this they project onto whichever segment happens to be nearest and become
    /// maneuvers at a place the rider never passes.
    static let maximumCueSnapMeters = 50.0

    // MARK: - Entry points

    /// The maneuvers for a route, cues first and polyline geometry as the fallback.
    static func maneuvers(for detail: RouteDetail) -> [Maneuver] {
        maneuvers(coordinates: detail.coordinates, cuePoints: detail.cuePoints)
    }

    /// - Note: the cue path wins whenever it produces anything at all, but the test is
    ///   whether a cue *resolved*, not whether the file contained one. Garmin Connect and
    ///   Strava both export a route with a single `<wpt>` named "Start"; keying off mere
    ///   presence would let that one unusable cue suppress the geometry scan and ship a
    ///   route with no maneuvers whatsoever.
    static func maneuvers(coordinates: [RouteCoordinate], cuePoints: [RouteCuePoint]) -> [Maneuver] {
        guard coordinates.count > 1 else { return [] }
        let turns = geometricTurns(coordinates)

        if !cuePoints.isEmpty {
            let cued = maneuversFromCues(cuePoints, coordinates: coordinates, turns: turns)
            if !cued.isEmpty { return cued }
        }
        return separated(turns.map {
            (
                maneuver: Maneuver(
                    coordinate: $0.coordinate,
                    direction: $0.direction,
                    name: nil,
                    distanceAlongRouteMeters: $0.distanceAlongRouteMeters
                ),
                magnitude: abs($0.totalDegrees)
            )
        })
    }

    // MARK: - Geometry

    /// One detected turn in the polyline: where it is, and how far the road turns through it.
    struct Turn: Equatable, Sendable {
        var totalDegrees: Double
        var direction: Maneuver.Direction
        var coordinate: RouteCoordinate
        var distanceAlongRouteMeters: Double
    }

    /// Every turn the polyline makes, in route order, before any cue has a say.
    static func geometricTurns(_ coordinates: [RouteCoordinate]) -> [Turn] {
        let step = adaptiveStep(coordinates)
        let samples = RouteGeometry.resampled(coordinates, everyMeters: step)
        guard samples.count > 2 else { return [] }

        // The heading change at each interior sample: the difference between the heading of
        // the segment arriving at it and of the one leaving it.
        var changes: [(delta: Double, sample: (coordinate: RouteCoordinate, distanceAlongRouteMeters: Double))] = []
        var previousHeading: Double?
        for index in 0..<(samples.count - 1) {
            guard let heading = RouteGeometry.bearingDegrees(
                from: samples[index].coordinate,
                to: samples[index + 1].coordinate
            ) else { continue }
            defer { previousHeading = heading }
            guard let previous = previousHeading else { continue }
            changes.append((normalized(heading - previous), samples[index]))
        }

        var turns: [Turn] = []
        for run in runs(of: changes) {
            let total = run.reduce(0) { $0 + $1.delta }
            guard let direction = direction(forTotalDegrees: total),
                  let first = run.first, let last = run.last else { continue }

            // A large turn taken gently enough is the road, not a maneuver.
            let span = last.sample.distanceAlongRouteMeters - first.sample.distanceAlongRouteMeters + step
            guard span / (abs(total) * .pi / 180) <= maximumTurnRadiusMeters else { continue }

            // Placed where half the turning is done, not at the first sample of the run:
            // anchoring to the start biases a symmetric corner early by half the run length.
            var accumulated = 0.0
            var apex = first.sample
            for change in run {
                accumulated += abs(change.delta)
                if accumulated >= abs(total) / 2 { apex = change.sample; break }
            }
            turns.append(Turn(
                totalDegrees: total,
                direction: direction,
                coordinate: apex.coordinate,
                distanceAlongRouteMeters: apex.distanceAlongRouteMeters
            ))
        }
        return turns
    }

    /// A short route still has to be measurable: clamping the step keeps enough samples to
    /// difference rather than returning nothing for a route only a few steps long.
    private static func adaptiveStep(_ coordinates: [RouteCoordinate]) -> Double {
        let total = RouteGeometry.distanceMeters(coordinates)
        guard total > 0 else { return resampleStepMeters }
        return min(resampleStepMeters, total / 4)
    }

    private typealias Change = (delta: Double, sample: (coordinate: RouteCoordinate, distanceAlongRouteMeters: Double))

    /// Groups consecutive heading changes into turns.
    ///
    /// A turn continues while the road keeps bending the same way, and ends either when it
    /// starts bending the other way or when it has run straight for `minimumSeparationMeters`.
    /// Straight samples in the middle neither extend nor end it, which is what lets a corner
    /// drawn as a polyline arc survive a flat spot in the middle of it.
    private static func runs(of changes: [Change]) -> [[Change]] {
        var runs: [[Change]] = []
        var current: [Change] = []
        // Samples bending against the run so far, held back until it is clear whether they
        // are scatter (in which case they belong to this turn) or the start of the next turn.
        var pending: [Change] = []
        var lastTurning: Double?
        var sign = 0.0

        func close() {
            if !current.isEmpty { runs.append(current) }
            current = []
            lastTurning = nil
        }

        for change in changes {
            let turning = abs(change.delta) >= turningNoiseFloorDegrees

            if !current.isEmpty, let last = lastTurning,
               change.sample.distanceAlongRouteMeters - last > minimumSeparationMeters {
                // The road has run straight for long enough that the next bend is its own turn.
                current.append(contentsOf: pending)
                pending = []
                close()
            }

            if current.isEmpty {
                if !pending.isEmpty {
                    current = pending
                    lastTurning = pending.last?.sample.distanceAlongRouteMeters
                    sign = pending.reduce(0) { $0 + $1.delta }
                    pending = []
                }
                if current.isEmpty {
                    guard turning else { continue }
                    current = [change]
                    lastTurning = change.sample.distanceAlongRouteMeters
                    sign = change.delta
                    continue
                }
            }

            guard turning else {
                // Straight samples belong to whichever side of the decision is still open.
                if pending.isEmpty { current.append(change) } else { pending.append(change) }
                continue
            }

            if (change.delta > 0) == (sign > 0) {
                // The road resumed its original direction, so whatever bent the other way was
                // scatter and belongs to this turn after all.
                current.append(contentsOf: pending)
                pending = []
                current.append(change)
                lastTurning = change.sample.distanceAlongRouteMeters
                sign = change.delta
                continue
            }

            pending.append(change)
            let counterTurn = abs(pending.reduce(0) { $0 + $1.delta })
            if counterTurn >= reversalThresholdDegrees {
                close()
                current = pending
                lastTurning = pending.last?.sample.distanceAlongRouteMeters
                sign = pending.reduce(0) { $0 + $1.delta }
                pending = []
            }
        }
        current.append(contentsOf: pending)
        close()
        return runs
    }

    // MARK: - Classification

    /// The maneuver a total heading change amounts to, or nil when the road merely bends.
    ///
    /// Kept separate from the geometry so the thresholds can be tested at exactly their
    /// boundary. A fixture built to bend "exactly 40°" measures 39.999994° once it has been
    /// through latitude and longitude and back, so a test that looks like it asserts the
    /// boundary asserts the opposite of what it appears to.
    static func direction(forTotalDegrees total: Double) -> Maneuver.Direction? {
        guard total.isFinite, abs(total) >= turnThresholdDegrees else { return nil }
        guard abs(total) < uTurnThresholdDegrees else { return .uTurn }
        return total > 0 ? .right : .left
    }

    /// Signed difference of two headings, in `(-180, 180]`. Positive is a right turn.
    static func normalized(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value <= -180 { value += 360 }
        if value > 180 { value -= 360 }
        return value
    }

    // MARK: - Cues

    /// What a cue's own words say about it.
    enum CueReading: Equatable {
        /// The cue names a direction.
        case direction(Maneuver.Direction)
        /// The cue says it is not a turn — a food stop, a summit, "continue straight".
        /// Distinct from `unstated` because it must *suppress* the geometric fallback: a
        /// "Continue straight on Main St" cue that happens to land on a bend would otherwise
        /// be handed the bend's angle and become a turn the file explicitly denied.
        case notATurn
        /// The cue is a turn but does not say which way; ask the polyline.
        case unstated
    }

    private static func maneuversFromCues(
        _ cuePoints: [RouteCuePoint],
        coordinates: [RouteCoordinate],
        turns: [Turn]
    ) -> [Maneuver] {
        let cumulative = RouteGeometry.cumulativeDistances(coordinates)

        // Index carried through the sort. Cues arrive as every <wpt> followed by every named
        // <rtept> (`GPXRouteImporter.swift:71-72`), so they are in neither route nor document
        // order; and a turn cued as both projects to an identical distance, where an unstable
        // sort would leave it unspecified which of the two names the rider is shown.
        var resolved: [(order: Int, maneuver: Maneuver)] = []
        for (order, cue) in cuePoints.enumerated() {
            let reading = self.reading(of: cue)
            guard reading != .notATurn else { continue }

            let point = RouteCoordinate(latitude: cue.latitude, longitude: cue.longitude, elevationMeters: nil)
            guard let projection = RouteGeometry.projection(of: point, onto: coordinates, cumulative: cumulative),
                  projection.offsetMeters <= maximumCueSnapMeters else { continue }

            let direction: Maneuver.Direction
            switch reading {
            case .direction(let stated):
                direction = stated
            case .unstated:
                // The file says there is a turn here but not which way, so read it off the
                // polyline — the nearest turn the geometry found, if it found one close by.
                guard let nearest = turns.min(by: {
                    abs($0.distanceAlongRouteMeters - projection.distanceAlongRouteMeters)
                        < abs($1.distanceAlongRouteMeters - projection.distanceAlongRouteMeters)
                }), abs(nearest.distanceAlongRouteMeters - projection.distanceAlongRouteMeters) <= minimumSeparationMeters
                else { continue }
                direction = nearest.direction
            case .notATurn:
                continue
            }

            resolved.append((order, Maneuver(
                coordinate: projection.coordinate,
                direction: direction,
                name: cue.name,
                distanceAlongRouteMeters: projection.distanceAlongRouteMeters
            )))
        }

        let ordered = resolved.sorted {
            $0.maneuver.distanceAlongRouteMeters == $1.maneuver.distanceAlongRouteMeters
                ? $0.order < $1.order
                : $0.maneuver.distanceAlongRouteMeters < $1.maneuver.distanceAlongRouteMeters
        }
        // A cue carries no angle, so how much of a maneuver it is is all there is to rank on.
        // Two cues for one turn that agree on direction therefore resolve to the earlier of
        // them in importer order, which the sort above has already made deterministic.
        return separated(ordered.map { ($0.maneuver, Double($0.maneuver.direction.severity)) })
    }

    /// Reads a cue's `type`, then its `name`, then its `<desc>` — the order they get more
    /// verbose and less reliable in. RideWithGPS states the turn in `type` ("Left"); Komoot
    /// leaves it nil and puts the instruction in `name`; some exporters use only `<desc>`.
    static func reading(of cue: RouteCuePoint) -> CueReading {
        for text in [cue.type, cue.name, cue.cueDescription] {
            guard let text, !text.isEmpty else { continue }
            let reading = self.reading(ofText: text)
            if reading != .unstated { return reading }
        }
        return .unstated
    }

    /// Words that mean "this is a turn", and words that mean "this is not one".
    private static let notATurnWords: Set<String> = [
        "start", "end", "finish", "food", "water", "summit", "generic", "danger",
        "straight", "continue", "control", "rest", "photo", "poi",
        // Filler, so that "Water stop" and "Rest area" are classified rather than falling
        // through to the geometry fallback and picking up whatever bend they landed near.
        "stop", "area", "point", "break", "aid", "station", "the", "a", "on", "at",
    ]
    private static let slightWords: Set<String> = ["slight", "bear", "keep"]

    static func reading(ofText text: String) -> CueReading {
        // Only the instruction itself, never the street it names: "Turn left onto Right Fork
        // Road" is a left, and word-boundary matching alone does not save you from it.
        var clause = text.lowercased()
        for separator in [" onto ", " on ", " at ", " to ", " towards ", " toward "] {
            if let range = clause.range(of: separator) {
                clause = String(clause[clause.startIndex..<range.lowerBound])
                break
            }
        }
        if clause.contains("u-turn") || clause.contains("uturn") || clause.contains("u turn") {
            return .direction(.uTurn)
        }

        let words = clause.split(whereSeparator: { !$0.isLetter }).map(String.init)
        guard !words.isEmpty else { return .unstated }
        if words.allSatisfy({ notATurnWords.contains($0) }) { return .notATurn }

        // The qualifier has to be read before the side, or every "slight left" is just a left.
        for (index, word) in words.enumerated() {
            let side: Maneuver.Direction?
            switch word {
            case "left": side = .left
            case "right": side = .right
            default: side = nil
            }
            guard let side else { continue }
            let qualifier = index > 0 ? words[index - 1] : ""
            if slightWords.contains(qualifier) {
                return .direction(side == .left ? .slightLeft : .slightRight)
            }
            return .direction(side)
        }
        return .unstated
    }

    // MARK: - Separation

    /// Collapses maneuvers closer together than `minimumSeparationMeters`.
    ///
    /// The survivor is the *sharper* turn, not the first. Keeping the first would announce a
    /// 45° jog and then say nothing about the 90° turn 20 m after it, which is the one the
    /// rider actually has to make.
    private static func separated(_ candidates: [(maneuver: Maneuver, magnitude: Double)]) -> [Maneuver] {
        var kept: [(maneuver: Maneuver, magnitude: Double)] = []
        for candidate in candidates {
            guard let last = kept.last,
                  candidate.maneuver.distanceAlongRouteMeters
                      - last.maneuver.distanceAlongRouteMeters < minimumSeparationMeters
            else {
                kept.append(candidate)
                continue
            }
            if candidate.magnitude > last.magnitude { kept[kept.count - 1] = candidate }
        }
        return kept.map(\.maneuver)
    }
}

/// One turn on a route: where it is, which way it goes, and how far into the route it falls.
///
/// Never persisted — derived at route load from `RouteDetail`, so a change to the derivation
/// takes effect on routes that were imported before it.
struct Maneuver: Equatable, Sendable {
    enum Direction: Equatable, Sendable, CaseIterable {
        case slightLeft, slightRight, left, right, uTurn

        /// How much of a maneuver this is, for deciding which of two collapsed turns survives.
        var severity: Int {
            switch self {
            case .slightLeft, .slightRight: 0
            case .left, .right: 1
            case .uTurn: 2
            }
        }

        var isLeft: Bool { self == .left || self == .slightLeft }
    }

    var coordinate: RouteCoordinate
    var direction: Direction
    /// The cue's own words, where a cue supplied this maneuver. Nil on the geometric path,
    /// which has no name to give it.
    var name: String?
    var distanceAlongRouteMeters: Double
}
