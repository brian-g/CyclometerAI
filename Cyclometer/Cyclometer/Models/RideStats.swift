import Foundation

/// S15's Stats section (#251) and metric sections (#536): the aggregates `Ride` stores, read on the screen's own load
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
    /// W23's series, stored with the total (#536): nil exactly when it is.
    var calorieSeries: [CaloriePoint]? = nil
    /// W3's moving seconds (`Ride.speedSampleCount`), for the Time section (#536).
    var movingSeconds: Int = 0
    /// W5's time at each whole rpm and time coasting (#340), for the Cadence sections (#536);
    /// zones resolve against S12's as they are now.
    var cadenceSecondsByRPM: [Int: TimeInterval] = [:]
    var cadenceCoastingSeconds: TimeInterval = 0
}
