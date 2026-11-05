import Foundation

/// S15's Stats section (#251): the aggregates `Ride` stores, read on the screen's own load
/// rather than carried on every S14 row in `RideListSummary`. Each optional is hidden on S15
/// when nil (#460).
struct RideStats: Sendable, Equatable {
    var averageSpeedMPS: Double
    var maxSpeedMPS: Double
    /// Nil when no cadence sensor reported — a real 0 rpm average is not the same thing.
    var averageCadenceRPM: Int?
    var maxCadenceRPM: Int?
    /// Nil when no radar was paired, as on `Ride`.
    var vehiclePassCount: Int?
    /// The route the ride followed, nil for a free ride — S15's link to S20 (#426). It can
    /// outlive the route itself: deleting a route leaves `Ride.routeId` dangling.
    var routeId: UUID? = nil
    /// The denormalized name of the route the ride followed, nil for a free ride — S10's Route
    /// row and default title (#249).
    var routeName: String? = nil
    /// Nil when no heart rate was recorded (#460).
    var averageHeartRateBPM: Int? = nil
    var maxHeartRateBPM: Int? = nil
    /// Stored at the finish (#460): nil for a ride with no altitude, and for one still waiting on
    /// `RideFinishStats.backfill`.
    var ascentMeters: Double? = nil
    var descentMeters: Double? = nil
    /// Stored at the finish (#460): nil without a body mass in Health.
    var activeKilocalories: Double? = nil
}
