import Foundation

/// Minimal `Sendable` read of a completed `Ride` for the Rides tab list (#247) — name,
/// date, distance and duration, the same granularity `RouteSummary` gives S19's list.
/// Carries S14's map thumbnail, both appearances, as stored on `Ride` (#177, #248). No
/// HR/cadence/vehicle-pass data (S15's detail screen reads those separately, per-ride, via
/// `fetchTrackPoints`/`fetchVehiclePassEvents`).
struct RideListSummary: Sendable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var startedAt: Date
    var distanceMeters: Double
    var durationSeconds: TimeInterval
    /// PNGs rendered once after the ride ended (#177). Nil for a ride recorded before then,
    /// one with no GPS track, or one whose capture hasn't succeeded yet.
    var mapThumbnailLight: Data? = nil
    var mapThumbnailDark: Data? = nil
}
