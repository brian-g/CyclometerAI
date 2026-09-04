import Foundation

/// Snapshot of a ride's running aggregates, written to the persisted `Ride` both at
/// the 30s checkpoint and (with final values) at ride end. Mirrors TrackPointDTO's
/// role as a boundary DTO — no persistence-layer types leak through it.
struct RideSummaryUpdate: Sendable, Equatable {
    var rideId: UUID
    var recordingState: Ride.RecordingState = .active
    var durationSeconds: TimeInterval
    var distanceMeters: Double
    var averageSpeedMPS: Double
    var maxSpeedMPS: Double
    var averageHeartRateBPM: Int?
    var maxHeartRateBPM: Int?
    var averageCadenceRPM: Int?
    var maxCadenceRPM: Int?
    var vehiclePassCount: Int?   // ActiveRideFeature's running count of confirmed passes (#172)
    /// See `Ride.isAutoPaused`/`Ride.zeroSpeedSeconds`/the three sample-count
    /// fields (#175) — defaulted so every pre-#175 call site keeps compiling.
    var isAutoPaused: Bool = false
    var zeroSpeedSeconds: Int = 0
    var speedSampleCount: Int = 0
    var hrSampleCount: Int = 0
    var cadenceSampleCount: Int = 0
}
