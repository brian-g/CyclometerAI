import Foundation

/// A vehicle detected by the Garmin Varia radar.
/// RTL515 / RCT715 report up to 8 targets within ~140 m.
struct RadarTarget: Equatable, Identifiable, Sendable {
    let id: UUID
    /// Relative closing velocity in m/s (positive = approaching).
    var relativeVelocityMPS: Double
    /// Range to target in metres (0–140 m).
    var rangeMetres: Double
    /// Derived threat classification.
    var threatLevel: ThreatLevel

    enum ThreatLevel: Equatable, Sendable {
        case allClear   // L0 — no active threats
        case warning    // L2 — vehicle approaching, time to act
        case danger     // L3 — immediate threat, full alert
    }
}
