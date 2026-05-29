import Foundation

/// Karvonen heart-rate reserve zone model.
/// Zone is computed at query time — never stored as persisted state.
enum HeartRateZone: Int, CaseIterable, Equatable {
    case zone1 = 1  // Recovery       < 60% HRR
    case zone2 = 2  // Endurance      60–70% HRR
    case zone3 = 3  // Tempo          70–80% HRR
    case zone4 = 4  // Threshold      80–90% HRR
    case zone5 = 5  // VO₂ Max        ≥ 90% HRR

    /// Karvonen formula: intensity = (bpm − restingHR) / (maxHR − restingHR)
    static func zone(bpm: Int, maxHR: Int, restingHR: Int) -> HeartRateZone {
        let hrr = Double(maxHR - restingHR)
        guard hrr > 0 else { return .zone1 }
        let intensity = Double(bpm - restingHR) / hrr
        switch intensity {
        case ..<0.60: return .zone1
        case ..<0.70: return .zone2
        case ..<0.80: return .zone3
        case ..<0.90: return .zone4
        default:      return .zone5
        }
    }
}
