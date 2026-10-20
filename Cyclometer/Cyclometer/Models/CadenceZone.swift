import SwiftUI

/// The five cadence intensity zones (#79), from recovery spinning to sprinting. Their rpm
/// boundaries are the rider's, set in S12 (`CadenceZoneBoundaries`). Drives the shaded bands
/// behind the W5 cadence watermark and the detail sheet's "Time in Zones" breakdown.
///
/// Replaces #38's four fixed efficiency zones (grinding / transition / optimal / overspin).
enum CadenceZone: Int, CaseIterable, Equatable, Sendable {
    case zone1 = 1, zone2, zone3, zone4, zone5

    /// Band/treatment colour. The HR zone tokens, so cadence Z3 reads like HR Z3.
    var color: Color { .hrZone(rawValue) }

    /// S12's row name, also the detail sheet's.
    var displayName: String {
        switch self {
        case .zone1: "Recovery"
        case .zone2: "Endurance"
        case .zone3: "Steady State"
        case .zone4: "Race Pace"
        case .zone5: "Sprint"
        }
    }
}

/// The rider's cadence zone boundaries (#79): the lower rpm of zones 2–5, strictly rising.
/// Zones are half-open, `[lower, next lower)`. Stored whole in `AppPreferences` — no framework
/// owns cadence zones, so there is no override to resolve against.
struct CadenceZoneBoundaries: Codable, Equatable, Sendable {
    /// Where S12 shows Z1 starting. Display only: a pedalling reading below it is still Z1,
    /// as a heart rate below resting is HR zone 1.
    static let zone1FloorRPM = 60
    /// The W5 charts' y-domain ceiling. Z5 must start below it, or its band would never show.
    static let ceilingRPM = 150
    /// The issue's defaults: Z1 60–70, Z2 70–85, Z3 85–95, Z4 95–110, Z5 110+.
    static let `default` = CadenceZoneBoundaries(lowerBoundsRPM: [70, 85, 95, 110])!

    /// Lower rpm of zones 2–5. Every zone is at least 1 rpm wide, Z1 from its floor and Z5 up
    /// to the ceiling.
    let lowerBoundsRPM: [Int]

    init?(lowerBoundsRPM: [Int]) {
        guard Self.isValid(lowerBoundsRPM) else { return nil }
        self.lowerBoundsRPM = lowerBoundsRPM
    }

    private static func isValid(_ lowerBounds: [Int]) -> Bool {
        let edges = [zone1FloorRPM] + lowerBounds + [ceilingRPM]
        return lowerBounds.count == CadenceZone.allCases.count - 1
            && zip(edges, edges.dropFirst()).allSatisfy { $0 < $1 }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let lowerBounds = try container.decode([Int].self, forKey: .lowerBoundsRPM)
        guard Self.isValid(lowerBounds) else {
            throw DecodingError.dataCorruptedError(
                forKey: .lowerBoundsRPM, in: container, debugDescription: "Cadence zone boundaries out of order"
            )
        }
        self.lowerBoundsRPM = lowerBounds
    }

    /// The zone a pedalling reading falls into. Below Z2 is Z1, whatever the floor.
    func zone(forRPM rpm: Double) -> CadenceZone {
        CadenceZone.allCases.dropFirst().last { rpm >= Double(lowerBound(of: $0)) } ?? .zone1
    }

    /// The lowest whole rpm in `zone`, as S12 shows it.
    func lowerBound(of zone: CadenceZone) -> Int {
        zone == .zone1 ? Self.zone1FloorRPM : lowerBoundsRPM[zone.rawValue - 2]
    }

    /// The highest whole rpm in `zone`; nil for Z5, which has no upper bound.
    func upperBound(of zone: CadenceZone) -> Int? {
        zone == .zone5 ? nil : lowerBoundsRPM[zone.rawValue - 1] - 1
    }

    /// "60-69", or "110+" for Z5 — S12's and the detail sheet's range, written as S12's HR rows are.
    func rangeText(for zone: CadenceZone) -> String {
        upperBound(of: zone).map { "\(lowerBound(of: zone))-\($0)" } ?? "\(lowerBound(of: zone))+"
    }

    /// Half-open chart band for `zone`: Z1 runs from 0 so the chart has no unshaded strip, and
    /// Z5 up to `ceiling`. Bounds are clamped to `ceiling`, so a low one can't invert a band.
    func bandRange(for zone: CadenceZone, ceiling: Double) -> Range<Double> {
        let lower = zone == .zone1 ? 0 : Double(lowerBound(of: zone))
        let upper = upperBound(of: zone).map { Double($0 + 1) } ?? ceiling
        return min(lower, ceiling)..<min(upper, ceiling)
    }

    /// A copy with the boundary after `zone` moved by `delta` rpm, or nil when that would empty a
    /// zone or leave the floor-to-ceiling span. Z5 has no boundary after it, so it is always nil.
    func stepping(afterZone zone: CadenceZone, by delta: Int) -> CadenceZoneBoundaries? {
        guard zone != .zone5 else { return nil }
        var lowerBounds = lowerBoundsRPM
        lowerBounds[zone.rawValue - 1] += delta
        return CadenceZoneBoundaries(lowerBoundsRPM: lowerBounds)
    }
}
