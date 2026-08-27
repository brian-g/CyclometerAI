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
        // Not currently reachable from live BLE data — VariaRadarClient.parseAlert
        // only ever tags a parsed target .warning or .danger, since the real wire
        // payload only lists vehicles being actively tracked as a threat. Kept for
        // previews/tests and because PRD §8.2/UX.md still describe it as a dot state.
        case allClear   // L0 — no active threats
        case warning    // L2 — vehicle approaching, time to act
        case danger     // L3 — immediate threat, full alert
    }
}
