import Foundation

/// Tags which sensor produced a track-point field (speed, heart rate, cadence, power).
/// `.none` means the field is omitted from GPX export entirely, not written as zero.
enum SensorSource: String, Codable, Equatable, Sendable {
    case bleHR
    case bleWheel
    case bleCadence
    case blePower
    case appleWatch
    case gps
    case none
}
