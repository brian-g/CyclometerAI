import Foundation

/// Minimal `Sendable` read of a completed `Ride`, carrying only what S20's Previous
/// Rides rows show for a route — when it was ridden and how long it took — and the title
/// S15 opens under when a row is tapped (#426). Not a general-purpose Ride DTO — see
/// `RideExportMetadata` for GPX export's read and `RideSummaryUpdate` for the write side.
struct RouteRideSummary: Sendable, Equatable, Identifiable {
    var id: UUID { rideId }
    var rideId: UUID
    /// "" for a ride S10 never named, as on `RideListSummary`.
    var title: String
    var startedAt: Date
    var endedAt: Date?
    var durationSeconds: TimeInterval
    var distanceMeters: Double
}
