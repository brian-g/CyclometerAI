import Foundation

/// Minimal `Sendable` read of a completed `Ride` for the Rides tab list (#247) — name,
/// date, distance and duration, the same granularity `RouteSummary` gives S19's list.
/// No map thumbnail: S14 reads each visible row's through `fetchRideMapThumbnail` (#248),
/// so a reload doesn't pull every ride's images off disk. No HR/cadence/vehicle-pass data (S15's detail screen reads those separately, per-ride, via
/// `fetchTrackPoints`/`fetchVehiclePassEvents`).
struct RideListSummary: Sendable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var startedAt: Date
    var distanceMeters: Double
    var durationSeconds: TimeInterval
}

/// A ride's stored map thumbnail, both appearances (#177): PNGs rendered once after the ride
/// ended.
struct RideMapThumbnailData: Sendable, Equatable {
    var light: Data
    var dark: Data
}
