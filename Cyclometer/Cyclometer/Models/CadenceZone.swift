import SwiftUI

/// Pedalling-efficiency cadence zones with fixed RPM thresholds (unlike
/// `HeartRateZone`, which is derived from the rider's HR reserve). Drives the
/// shaded bands behind the W5 cadence watermark and the "Time in Zones" breakdown.
///
/// Thresholds (issue #38): grinding < 70, optimal 85–100, over-spinning > 100.
/// 70–85 is a neutral transition band between grinding and optimal.
enum CadenceZone: CaseIterable, Equatable {
    case grinding    // < 70   — mashing a big gear
    case transition  // 70–85  — between grinding and optimal
    case optimal     // 85–100 — efficient spin
    case overspin    // > 100  — spinning out

    /// Half-open RPM range `[lower, upper)`. `overspin` is upper-bounded by the
    /// chart's y-domain ceiling rather than infinity so it can render as a band.
    /// Bounds are clamped to `ceiling` so a low ceiling can never produce an
    /// invalid (lowerBound > upperBound) range.
    func rpmRange(ceiling: Double) -> Range<Double> {
        func clamp(_ value: Double) -> Double { min(value, ceiling) }
        switch self {
        case .grinding:   return 0..<clamp(70)
        case .transition: return clamp(70)..<clamp(85)
        case .optimal:    return clamp(85)..<clamp(100)
        case .overspin:   return clamp(100)..<ceiling
        }
    }

    /// Band/treatment colour. Reuses the shared rating tokens; the neutral
    /// transition band uses tertiary text so it reads as "no judgement".
    var color: Color {
        switch self {
        case .grinding:   return .cyRatingOkay
        case .transition: return .cyTextTertiary
        case .optimal:    return .cyRatingGood
        case .overspin:   return .cyRatingBad
        }
    }

    /// Short label for the detail sheet's zone breakdown.
    var label: String {
        switch self {
        case .grinding:   return "<70"
        case .transition: return "70–85"
        case .optimal:    return "85–100"
        case .overspin:   return "100+"
        }
    }

    /// The zone a given RPM reading falls into.
    static func zone(forRPM rpm: Double) -> CadenceZone {
        switch rpm {
        case ..<70:  return .grinding
        case ..<85:  return .transition
        case ..<100: return .optimal
        default:     return .overspin
        }
    }
}
