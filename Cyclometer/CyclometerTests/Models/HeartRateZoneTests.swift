import Testing
import Foundation
@testable import Cyclometer

@Suite("HeartRateZone")
struct HeartRateZoneTests {

    /// The §8 worked example: resting 60, max 190, HRR 130.
    private static let resting = 60
    private static let max = 190

    @Test(
        "Zone ranges match the §8 worked example",
        arguments: [
            (HeartRateZone.zone1, 60...137),
            (.zone2, 138...150),
            (.zone3, 151...163),
            (.zone4, 164...176),
            (.zone5, 177...190)
        ]
    )
    func workedExampleRanges(_ zone: HeartRateZone, _ expected: ClosedRange<Int>) {
        #expect(HeartRateZone.bounds(for: zone, maxHR: Self.max, restingHR: Self.resting) == expected)
    }

    @Test("Zone 1 opens at the resting rate and zone 5 closes at the max")
    func endZonesAnchorToTheProfile() {
        let z1 = HeartRateZone.bounds(for: .zone1, maxHR: Self.max, restingHR: Self.resting)
        let z5 = HeartRateZone.bounds(for: .zone5, maxHR: Self.max, restingHR: Self.resting)

        #expect(z1.lowerBound == Self.resting)
        #expect(z5.upperBound == Self.max)
    }

    /// A threshold landing between two bpm must round *up*, or the boundary bpm
    /// falls in the zone below and the two directions disagree.
    @Test("A fractional threshold rounds up to the first bpm inside the zone")
    func fractionalThresholdRoundsUp() {
        // HRR 101 → zone 2 opens at 60.6% of reserve = 60 + ⌈60.6⌉ = 121.
        let bounds = HeartRateZone.bounds(for: .zone2, maxHR: 161, restingHR: 60)

        #expect(bounds.lowerBound == 121)
        #expect(HeartRateZone.zone(bpm: 121, maxHR: 161, restingHR: 60) == .zone2)
        #expect(HeartRateZone.zone(bpm: 120, maxHR: 161, restingHR: 60) == .zone1)
    }

    /// The strongest available check, and the one that keeps `bounds` honest: the
    /// exact-integer inverse must agree with §8's floating-point forward formula at
    /// every edge, for every profile the app can actually hold.
    ///
    /// Swept over exactly what `RiderProfile` validation admits — including the
    /// `minimumHRReserve` floor, which exists precisely because the two directions
    /// stop agreeing below it (a reserve of 7 or less collapses two zone boundaries
    /// onto one bpm). Widening this sweep past validation will fail, and correctly so.
    @Test("Every range endpoint maps back to its own zone across the valid profiles")
    func rangesRoundTripAgainstTheForwardFormula() {
        for resting in RiderProfile.restingValidRange {
            for maxHR in RiderProfile.maxValidRange
            where maxHR - resting >= RiderProfile.minimumHRReserve {
                for zone in HeartRateZone.allCases {
                    let bounds = HeartRateZone.bounds(for: zone, maxHR: maxHR, restingHR: resting)

                    #expect(
                        HeartRateZone.zone(bpm: bounds.lowerBound, maxHR: maxHR, restingHR: resting) == zone,
                        "lower edge \(bounds.lowerBound) of \(zone) at resting \(resting) / max \(maxHR)"
                    )
                    // Zone 5's upper edge is maxHR, which is still zone 5.
                    #expect(
                        HeartRateZone.zone(bpm: bounds.upperBound, maxHR: maxHR, restingHR: resting) == zone,
                        "upper edge \(bounds.upperBound) of \(zone) at resting \(resting) / max \(maxHR)"
                    )
                }
            }
        }
    }

    /// No gap and no overlap is representable — the invariant #103's steppers rely
    /// on when they adjust a boundary.
    @Test("Ranges are contiguous across zones 1–5")
    func rangesAreContiguous() {
        for resting in RiderProfile.restingValidRange {
            for maxHR in RiderProfile.maxValidRange
            where maxHR - resting >= RiderProfile.minimumHRReserve {
                let ranges = HeartRateZone.allCases.map {
                    HeartRateZone.bounds(for: $0, maxHR: maxHR, restingHR: resting)
                }
                for (lower, upper) in zip(ranges, ranges.dropFirst()) {
                    #expect(
                        upper.lowerBound == lower.upperBound + 1,
                        "gap between \(lower) and \(upper) at resting \(resting) / max \(maxHR)"
                    )
                }
            }
        }
    }

    @Test("The forward formula places the §8 boundaries in the upper zone")
    func forwardFormulaBoundaries() {
        #expect(HeartRateZone.zone(bpm: 137, maxHR: 190, restingHR: 60) == .zone1)
        #expect(HeartRateZone.zone(bpm: 138, maxHR: 190, restingHR: 60) == .zone2)
        #expect(HeartRateZone.zone(bpm: 151, maxHR: 190, restingHR: 60) == .zone3)
        #expect(HeartRateZone.zone(bpm: 164, maxHR: 190, restingHR: 60) == .zone4)
        #expect(HeartRateZone.zone(bpm: 177, maxHR: 190, restingHR: 60) == .zone5)
    }

    /// Degenerate profiles cannot arrive through `RiderProfile` validation, but the
    /// helper must not divide by zero or build a backwards range if one is passed.
    @Test("A non-positive reserve degrades instead of trapping")
    func nonPositiveReserve() {
        #expect(HeartRateZone.zone(bpm: 150, maxHR: 150, restingHR: 150) == .zone1)

        for zone in HeartRateZone.allCases {
            let bounds = HeartRateZone.bounds(for: zone, maxHR: 150, restingHR: 150)
            #expect(bounds.lowerBound <= bounds.upperBound)
        }
    }
}
