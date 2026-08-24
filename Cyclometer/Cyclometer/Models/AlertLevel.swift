import Foundation

/// Ride-level radar threat escalation (PRD §8.3, `Audio.md`). Derived independently
/// from the raw vehicle payload — NOT from `RadarTarget.ThreatLevel`, a separate,
/// coarser 3-tier per-vehicle dot color (PRD §8.2) that deliberately collapses
/// L1/L2 into one color band. The Varia payload's own byte 0 nominally carries a
/// 0–3 alert level too, but `VariaRadarClient.parseAlert` collapses it into
/// `ThreatLevel` and discards it — there is no shortcut available here.
enum AlertLevel: Int, CaseIterable, Comparable, Hashable, Sendable {
    case clear = 0, advisory = 1, caution = 2, danger = 3

    static func < (lhs: AlertLevel, rhs: AlertLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Below this closing-speed differential, an approaching vehicle is "low"
    /// (L1-eligible) rather than "moderate" (L2). Resolves UX.md's open threshold
    /// question (line 695) — PRD §8.3 names no number, only "low"/"moderate".
    static let moderateClosingSpeedKPH: Double = 15
    /// At/above this, any single vehicle is L3 — matches the `brRatingBad` dot
    /// threshold (PRD §8.2/§8.3).
    static let dangerClosingSpeedKPH: Double = 30

    /// Only approaching vehicles (positive closing speed) count toward any branch —
    /// a receding/stationary vehicle is "Safe" per PRD §8.2's dot table and
    /// shouldn't itself elevate the ride-level alert.
    static func level(for targets: [RadarTarget]) -> AlertLevel {
        let approaching = targets.filter { $0.relativeVelocityMPS > 0 }
        guard !approaching.isEmpty else { return .clear }
        let maxClosingSpeedKPH = approaching.map { $0.relativeVelocityMPS * 3.6 }.max() ?? 0
        if maxClosingSpeedKPH >= dangerClosingSpeedKPH { return .danger }
        if maxClosingSpeedKPH >= moderateClosingSpeedKPH || approaching.count >= 3 { return .caution }
        return .advisory
    }
}
