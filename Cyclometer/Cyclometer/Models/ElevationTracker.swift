import Foundation

/// The live ride's ascent, descent, grade and range (#387): W14–W18 and the Elevation sheet.
///
/// Fed once a recorded second — the altitude `AltitudeResolver` settled on, and the ride's distance
/// so far. Totals are running sums rather than something derived from `altitudeSamples`, which keeps
/// only the last hour.
struct ElevationTracker: Equatable, Sendable {
    /// The barometer resolves a fraction of a metre, but wind on the phone and a passing truck move
    /// it by about that much. One metre clears that and still banks a short roller. GPS uses the
    /// route's `RouteGeometry.elevationNoiseThresholdMeters`, since its altitude is noisier still.
    static let barometricNoiseMeters = 1.0

    /// What a resumed ride had before the kill, from its saved track: the `Ride` row deliberately
    /// stores no elevation (#284).
    struct Seed: Equatable, Sendable {
        var ascentMeters: Double
        var descentMeters: Double
        var highestMeters: Double
        var lowestMeters: Double

        /// Nil for a track with no altitude. The track doesn't record which source each altitude
        /// came from, so it takes GPS's floor — the stricter one, which can only undercount a
        /// barometric stretch, never invent climbing in a GPS one.
        init?(savedAltitudes altitudes: [Double]) {
            guard let highest = altitudes.max(), let lowest = altitudes.min() else { return nil }
            var gain = ElevationGainTally()
            for altitude in altitudes {
                gain.add(altitude, noiseMeters: RouteGeometry.elevationNoiseThresholdMeters)
            }
            self.init(ascentMeters: gain.gainMeters, descentMeters: gain.lossMeters,
                      highestMeters: highest, lowestMeters: lowest)
        }

        init(ascentMeters: Double, descentMeters: Double, highestMeters: Double, lowestMeters: Double) {
            self.ascentMeters = ascentMeters
            self.descentMeters = descentMeters
            self.highestMeters = highestMeters
            self.lowestMeters = lowestMeters
        }
    }

    private var gain = ElevationGainTally()
    /// Kept apart from `gain` so a seed that lands after the first live seconds adds to them rather
    /// than replacing them.
    private var seed: Seed?

    private var liveHighestMeters: Double?
    private var liveLowestMeters: Double?

    /// Rise over run across the last `RouteTerrain.gradeWindowMeters` ridden, in percent; nil until
    /// the ride has covered that far with an altitude.
    private(set) var gradePercent: Double?
    /// The ride's steepest grade up (positive) and down (negative); nil until it has had one.
    private(set) var steepestClimbPercent: Double?
    private(set) var steepestDescentPercent: Double?
    /// Altitude at each distance within the grade window, oldest first.
    private var window: [Point] = []
    private struct Point: Equatable, Sendable {
        let distance: Double
        let altitude: Double
    }

    var ascentMeters: Double { (seed?.ascentMeters ?? 0) + gain.gainMeters }
    var descentMeters: Double { (seed?.descentMeters ?? 0) + gain.lossMeters }
    var highestMeters: Double? { [seed?.highestMeters, liveHighestMeters].compactMap { $0 }.max() }
    var lowestMeters: Double? { [seed?.lowestMeters, liveLowestMeters].compactMap { $0 }.min() }

    mutating func record(altitude: Double, distanceMeters: Double, source: AltitudeResolver.Source) {
        let noise = source == .barometric ? Self.barometricNoiseMeters : RouteGeometry.elevationNoiseThresholdMeters
        gain.add(altitude, noiseMeters: noise)
        liveHighestMeters = max(liveHighestMeters ?? altitude, altitude)
        liveLowestMeters = min(liveLowestMeters ?? altitude, altitude)

        // Stopped, the run is unchanged and so is the grade.
        guard distanceMeters > (window.last?.distance ?? -.infinity) else { return }
        window.append(Point(distance: distanceMeters, altitude: altitude))
        let start = distanceMeters - RouteTerrain.gradeWindowMeters
        // Keeps the newest point at or before the window's start, so the run spans it in full.
        while window.count > 1, window[1].distance <= start { window.removeFirst() }
        guard let first = window.first, first.distance <= start else { return }

        let grade = (altitude - first.altitude) / (distanceMeters - first.distance)
        // Steeper than any road is noise in the altitude, not road: keep the last believable grade.
        guard abs(grade) <= RideEnergy.maxPlausibleGrade else { return }
        let percent = grade * 100
        gradePercent = percent
        if percent > 0 { steepestClimbPercent = max(steepestClimbPercent ?? 0, percent) }
        if percent < 0 { steepestDescentPercent = min(steepestDescentPercent ?? 0, percent) }
    }

    mutating func seed(_ seed: Seed) {
        self.seed = seed
    }
}
