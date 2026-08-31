import Foundation

/// Sensor-facing shape for a single 1Hz recorded sample. Optionals carry "no source"
/// here; sentinel encoding for CoreData (-1.0 / 0) happens only at the TrackPointMO
/// mapping boundary, never on this type.
struct TrackPointDTO: Sendable, Equatable {
    var id: UUID = UUID()
    var rideId: UUID
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var altitudeMeters: Double
    var horizontalAccuracyMeters: Double
    var speedMPS: Double?
    var speedSource: SensorSource
    var heartRateBPM: Int?
    var heartRateSource: SensorSource
    var cadenceRPM: Int?
    var powerWatts: Int?
}
