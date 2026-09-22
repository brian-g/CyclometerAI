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
    /// Which continuous stretch of riding this point belongs to (#263). Zero for the
    /// first, incremented by every resume, so a pause is a boundary in the data rather
    /// than something a reader has to infer from a time gap — a GPS dropout in a tunnel
    /// leaves the same gap and is not a pause.
    ///
    /// Last, with a default, so every existing `TrackPointDTO(...)` literal still compiles
    /// and still means what it did: one segment, index 0.
    var segmentIndex: Int = 0
}
