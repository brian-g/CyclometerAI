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

    /// Where the zone starts, as a whole-number percentage of heart-rate reserve.
    /// The same thresholds `zone(bpm:maxHR:restingHR:)` switches on, held as `Int`
    /// so the inverse below can do exact arithmetic instead of rounding a `Double`
    /// product back to a bpm.
    var lowerThresholdPercent: Int {
        switch self {
        case .zone1: 0
        case .zone2: 60
        case .zone3: 70
        case .zone4: 80
        case .zone5: 90
        }
    }

    /// The lowest bpm that falls in this zone: `restingHR + ⌈percent × HRR⌉`.
    ///
    /// Ceiling, not rounding — the threshold is inclusive at the bottom, so the
    /// boundary bpm belongs to the zone it opens.
    static func lowerBoundBPM(for zone: HeartRateZone, maxHR: Int, restingHR: Int) -> Int {
        let hrr = maxHR - restingHR
        guard hrr > 0 else { return restingHR }
        return restingHR + (zone.lowerThresholdPercent * hrr + 99) / 100
    }

    /// The bpm range this zone covers — what a zone table displays (UX.md §S12).
    ///
    /// Ranges are contiguous by construction: each zone ends one bpm below the next
    /// one's start, so no gap or overlap is representable.
    ///
    /// **Inverts `zone(bpm:maxHR:restingHR:)` within the reserve only.** The two ends
    /// are closed at the profile — zone 1 opens at `restingHR`, zone 5 closes at
    /// `maxHR` — because that is what a table should show. Readings outside the
    /// reserve are still classified: the forward formula puts a bpm below `restingHR`
    /// in zone 1 and one above `maxHR` in zone 5, and neither falls inside the range
    /// this returns. A caller displaying the table wants the closed form; one testing
    /// membership must use the forward formula.
    static func bounds(for zone: HeartRateZone, maxHR: Int, restingHR: Int) -> ClosedRange<Int> {
        let lower = lowerBoundBPM(for: zone, maxHR: maxHR, restingHR: restingHR)
        guard let next = HeartRateZone(rawValue: zone.rawValue + 1) else {
            return lower...max(lower, maxHR)
        }
        let upper = lowerBoundBPM(for: next, maxHR: maxHR, restingHR: restingHR) - 1
        // `max` only bites when HRR is too small to separate two zones, which the
        // validation bounds on RiderProfile make unreachable through the UI.
        return lower...max(lower, upper)
    }
}
