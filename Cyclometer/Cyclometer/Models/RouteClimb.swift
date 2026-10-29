import Foundation

/// A categorized climb as a ride follows it (#463): the `Climb` S20 lists, with its own stretch of
/// the route's smoothed elevation, so W22 can say how much climbing is left and draw the climb.
struct RouteClimb: Equatable, Sendable {
    let climb: Climb
    /// The smoothed elevation from the climb's start to its top, every `spacing` metres. It is the
    /// profile `RouteTerrain.analyze` found the climb on, so its last value is the climb's top.
    let elevations: [Double]
    let spacing: Double
    /// `elevations` averaged into at most `Watermark.bucketCount` points: W22's watermark.
    let profile: [Double]

    var startMeters: Double { climb.startMeters }
    var topMeters: Double { climb.startMeters + climb.lengthMeters }

    /// Nil when the climb doesn't lie on `smoothed`, which a stored analysis of a different
    /// polyline would.
    init?(_ climb: Climb, smoothed: [Double], spacing: Double) {
        guard spacing > 0 else { return nil }
        // `analyze` places a climb at a sample index times this same spacing, so these are exact.
        let first = Int((climb.startMeters / spacing).rounded())
        let last = Int(((climb.startMeters + climb.lengthMeters) / spacing).rounded())
        guard first >= 0, first < last, last < smoothed.count else { return nil }
        self.climb = climb
        self.elevations = Array(smoothed[first...last])
        self.spacing = spacing
        self.profile = elevations.buckets(to: Watermark.bucketCount).map { $0.reduce(0, +) / Double($0.count) }
    }

    /// The climbs of `analysis` on the route `coordinates` describes, through the same pipeline
    /// `RouteTerrain.analyze` used. Empty with no elevation.
    ///
    /// With no stored analysis, the route is analysed here: one imported before #252 has none until
    /// `backfillRouteTerrain` runs, which only the Routes tab triggers, and a ride started from
    /// elsewhere would otherwise read "No climbs ahead" on a hilly route.
    static func climbs(of analysis: RouteTerrainAnalysis?, on coordinates: [RouteCoordinate]) -> [RouteClimb] {
        guard let climbs = (analysis ?? RouteTerrain.analyze(coordinates))?.climbs, !climbs.isEmpty,
              let profile = RouteTerrain.gradeProfile(coordinates)
        else { return [] }
        return climbs.compactMap { RouteClimb($0, smoothed: profile.elevation, spacing: profile.spacing) }
    }

    /// The smoothed elevation `meters` along the route, between the samples either side of it, and
    /// held at the climb's ends outside it.
    func elevation(atMeters meters: Double) -> Double {
        let position = min(max((meters - startMeters) / spacing, 0), Double(elevations.count - 1))
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, elevations.count - 1)
        let t = position - Double(lower)
        return elevations[lower] + (elevations[upper] - elevations[lower]) * t
    }
}

/// What W22 shows at the rider's place on the route (#463).
enum ClimbReading: Equatable, Sendable {
    /// On `climb`: how far to its top, how much height is left to gain, and how far up it the
    /// rider is, 0–1.
    case climbing(RouteClimb, metersToTop: Double, metersToClimb: Double, fraction: Double)
    /// Between climbs: the next one, and how far to its start.
    case next(RouteClimb, metersToStart: Double)
    /// No climb on the rest of the route.
    case noClimbAhead

    /// Pure, on the lap's own progress: a loop's wrap takes `progressMeters` back to the start, so
    /// the first climb is ahead again on the second lap.
    ///
    /// The top counts as on the climb, so both distances read 0 there before it turns to the next.
    static func at(progressMeters progress: Double, climbs: [RouteClimb]) -> ClimbReading {
        if let climb = climbs.first(where: { $0.startMeters <= progress && progress <= $0.topMeters }) {
            // The top from the profile itself rather than the stored `topElevationMeters`, so it reads
            // 0 at the top even if the analysis came from an earlier run of the pipeline.
            let left = climb.elevations[climb.elevations.count - 1] - climb.elevation(atMeters: progress)
            return .climbing(
                climb,
                metersToTop: climb.topMeters - progress,
                metersToClimb: min(max(left, 0), climb.climb.gainMeters),
                fraction: climb.climb.lengthMeters > 0 ? (progress - climb.startMeters) / climb.climb.lengthMeters : 1
            )
        }
        if let next = climbs.first(where: { $0.startMeters > progress }) {
            return .next(next, metersToStart: next.startMeters - progress)
        }
        return .noClimbAhead
    }
}
