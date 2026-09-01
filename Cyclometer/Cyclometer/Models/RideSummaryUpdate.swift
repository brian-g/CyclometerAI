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
    var vehiclePassCount: Int?   // always nil until #172 wires real counting
}
