import Foundation

/// A single timestamped, valid altitude reading (metres) kept for the cadence sheet's
/// elevation watermark. Never built from an invalid fix (#303).
struct AltitudeSample: Equatable, Sendable {
    let time: Date
    let meters: Double
}
