import Foundation

/// Minimal `Sendable` read of a completed `Ride` for the Rides tab list (#247) — name,
/// date, distance and duration, the same granularity `RouteSummary` gives S19's list.
/// No thumbnail yet (stored on `Ride` since #177; S14's row reads it in #248) and no
/// HR/cadence/vehicle-pass data (S15's detail screen reads those separately, per-ride, via
/// `fetchTrackPoints`/`fetchVehiclePassEvents`).
struct RideListSummary: Sendable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var startedAt: Date
    var distanceMeters: Double
    var durationSeconds: TimeInterval
}
