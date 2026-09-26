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
    /// Becomes the workout's route, the map Fitness draws (#295). The persisted track, so
    /// already filtered of untrustworthy fixes (#210) and of anything recorded while paused.
    var trackPoints: [TrackPointDTO]
    /// `RideEnergy`'s estimate, written as an `activeEnergyBurned` sample so the workout earns
    /// Move credit (#276). Nil when Health has no body mass: no energy rather than a guessed weight.
    var activeEnergyKilocalories: Double?
}
