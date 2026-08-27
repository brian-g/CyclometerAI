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

    /// Single source of truth for the km/h ↔ m/s factor, shared with
    /// `VariaRadarClient.parseAlert`'s reverse conversion of the wire's whole-km/h
    /// speed byte. `Measurement<UnitSpeed>` was tried and rejected here: measured
    /// empirically, its kilometersPerHour coefficient is a rounded decimal, not
    /// exactly 1/3.6, and round-trips a whole-km/h value off by ~1e-5 — two orders
    /// of magnitude worse than plain division/multiplication by this constant.
    static let kphPerMPS: Double = 3.6

    /// Absorbs the plain-arithmetic round-trip error (~1e-15, per the measurement
    /// above) between `parseAlert`'s km/h→m/s conversion and this comparison's
    /// m/s→km/h one, so a genuine boundary value (a wire speed of exactly 15 or 30
    /// km/h) never misclassifies depending on which direction the round trip's
    /// float rounding happens to fall.
    private static let epsilon: Double = 1e-9

    /// Only approaching vehicles (positive closing speed) count toward any branch —
    /// a receding/stationary vehicle is "Safe" per PRD §8.2's dot table and
    /// shouldn't itself elevate the ride-level alert.
    static func level(for targets: [RadarTarget]) -> AlertLevel {
        let approaching = targets.filter { $0.relativeVelocityMPS > 0 }
        guard !approaching.isEmpty else { return .clear }
        let maxClosingSpeedKPH = approaching.map { $0.relativeVelocityMPS * kphPerMPS }.max() ?? 0
        if maxClosingSpeedKPH >= dangerClosingSpeedKPH - epsilon { return .danger }
        if maxClosingSpeedKPH >= moderateClosingSpeedKPH - epsilon || approaching.count >= 3 { return .caution }
        return .advisory
    }
}
