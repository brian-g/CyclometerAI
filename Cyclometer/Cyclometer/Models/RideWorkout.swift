import Foundation

/// A finished ride as `HealthKitClient.saveWorkout` writes it to Apple Health (UX.md §S10,
/// #250) — only what the `HKWorkout` carries, so no `@Model` crosses into the client.
struct RideWorkout: Sendable, Equatable {
    /// Becomes the workout's sync identifier, so writing the same ride again replaces its
    /// workout rather than adding a second one.
    var rideId: UUID
    var startedAt: Date
    var endedAt: Date
    var distanceMeters: Double
}
