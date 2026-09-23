import Foundation

/// S15's Stats section (#251): the aggregates `Ride` already stores, read on the screen's
/// own load rather than carried on every S14 row in `RideListSummary`.
struct RideStats: Sendable, Equatable {
    var averageSpeedMPS: Double
    var maxSpeedMPS: Double
    /// Nil when no cadence sensor reported — a real 0 rpm average is not the same thing.
    var averageCadenceRPM: Int?
    var maxCadenceRPM: Int?
    /// Nil when no radar was paired, as on `Ride`.
    var vehiclePassCount: Int?
}
