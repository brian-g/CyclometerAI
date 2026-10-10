import Foundation

/// Ascent and descent banked with hysteresis: a move counts only once it clears a noise floor from
/// the last banked *reference*, which then moves to it. Filtering each delta individually instead
/// would discard a real 500 m climb sampled in 0.5 m steps; moving the reference accumulates that
/// in full while still rejecting jitter about a level road.
///
/// One rule for a planned route (`RouteGeometry.elevationGainLoss`) and a ridden one
/// (`ElevationTracker`, #387), fed a sample at a time so the live ride needn't keep its history.
struct ElevationGainTally: Equatable, Sendable {
    private(set) var gainMeters = 0.0
    private(set) var lossMeters = 0.0
    private var reference: Double?

    /// `noiseMeters` per sample, not per tally: the ride's altitude source can change mid-ride, and
    /// the barometer's floor is a fraction of GPS's.
    mutating func add(_ elevation: Double, noiseMeters: Double) {
        guard let reference else {
            self.reference = elevation
            return
        }
        let delta = elevation - reference
        if delta >= noiseMeters {
            gainMeters += delta
            self.reference = elevation
        } else if delta <= -noiseMeters {
            lossMeters -= delta
            self.reference = elevation
        }
    }
}
