import Foundation

/// Minimal `Sendable` read of a completed `Ride`, carrying only what S20's Previous
/// Rides rows show for a route: when it was ridden and how long it took. Not a
/// general-purpose Ride DTO — see `RideExportMetadata` for GPX export's read and
/// `RideSummaryUpdate` for the write side.
struct RouteRideSummary: Sendable, Equatable, Identifiable {
    var id: UUID { rideId }
    var rideId: UUID
    var startedAt: Date
    var endedAt: Date?
    var durationSeconds: TimeInterval
    var distanceMeters: Double
}
