import Testing
import Foundation
@testable import Cyclometer

@Suite("HeartRateZone")
struct HeartRateZoneTests {

    /// The §8 worked example: resting 60, max 190, HRR 130.
    /// Named `maxHR`, not `max` — the latter would shadow `Swift.max` for every test
    /// in this type.
    private static let resting = 60
    private static let maxHR = 190

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
        #expect(HeartRateZone.bounds(for: zone, maxHR: Self.maxHR, restingHR: Self.resting) == expected)
    }

    @Test("Zone 1 opens at the resting rate and zone 5 closes at the max")
    func endZonesAnchorToTheProfile() {
        let z1 = HeartRateZone.bounds(for: .zone1, maxHR: Self.maxHR, restingHR: Self.resting)
        let z5 = HeartRateZone.bounds(for: .zone5, maxHR: Self.maxHR, restingHR: Self.resting)

        #expect(z1.lowerBound == Self.resting)
        #expect(z5.upperBound == Self.maxHR)
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
    /// Both invariants share one pass over the profile space — the sweep is the
    /// expensive part, and splitting it would mean keeping the same nested loop and
    /// `minimumHRReserve` filter in step in two places.
    ///
    /// Contiguity (no gap, no overlap) is the invariant #103's steppers rely on when
    /// they adjust a boundary.
    @Test("Ranges round-trip and stay contiguous across every valid profile")
    func rangesRoundTripAndAreContiguous() {
        for resting in RiderProfile.restingValidRange {
            for maxHR in RiderProfile.maxValidRange
            where maxHR - resting >= RiderProfile.minimumHRReserve {
                let ranges = HeartRateZone.allCases.map {
                    HeartRateZone.bounds(for: $0, maxHR: maxHR, restingHR: resting)
                }
                let profile = "at resting \(resting) / max \(maxHR)"

                for (zone, bounds) in zip(HeartRateZone.allCases, ranges) {
                    #expect(
                        HeartRateZone.zone(bpm: bounds.lowerBound, maxHR: maxHR, restingHR: resting) == zone,
                        "lower edge \(bounds.lowerBound) of \(zone) \(profile)"
                    )
                    // Zone 5's upper edge is maxHR, which is still zone 5.
                    #expect(
                        HeartRateZone.zone(bpm: bounds.upperBound, maxHR: maxHR, restingHR: resting) == zone,
                        "upper edge \(bounds.upperBound) of \(zone) \(profile)"
                    )
                }

                for (lower, upper) in zip(ranges, ranges.dropFirst()) {
                    #expect(
                        upper.lowerBound == lower.upperBound + 1,
                        "gap between \(lower) and \(upper) \(profile)"
                    )
                }
            }
        }
    }

    /// `bounds` closes at the profile's ends, so it does *not* invert the forward
    /// formula outside the reserve — the doc comment says so, and this pins it rather
    /// than leaving a reader to assume the round-trip above covers the open ends.
    @Test("Readings outside the reserve are classified but fall outside the ranges")
    func boundsAreClosedAtBothEnds() {
        let belowResting = 45
        let aboveMax = 210

        #expect(HeartRateZone.zone(bpm: belowResting, maxHR: Self.maxHR, restingHR: Self.resting) == .zone1)
        #expect(!HeartRateZone.bounds(for: .zone1, maxHR: Self.maxHR, restingHR: Self.resting).contains(belowResting))

        #expect(HeartRateZone.zone(bpm: aboveMax, maxHR: Self.maxHR, restingHR: Self.resting) == .zone5)
        #expect(!HeartRateZone.bounds(for: .zone5, maxHR: Self.maxHR, restingHR: Self.resting).contains(aboveMax))
    }

    @Test("The forward formula places the §8 boundaries in the upper zone")
    func forwardFormulaBoundaries() {
        #expect(HeartRateZone.zone(bpm: 137, maxHR: 190, restingHR: 60) == .zone1)
        #expect(HeartRateZone.zone(bpm: 138, maxHR: 190, restingHR: 60) == .zone2)
        #expect(HeartRateZone.zone(bpm: 151, maxHR: 190, restingHR: 60) == .zone3)
        #expect(HeartRateZone.zone(bpm: 164, maxHR: 190, restingHR: 60) == .zone4)
        #expect(HeartRateZone.zone(bpm: 177, maxHR: 190, restingHR: 60) == .zone5)
    }

    /// The S12 HR Zones row names (assets/UX.md §S12) — distinct from the PRD §8.5
    /// names in the case comments above, which are not UI copy.
    @Test("s12DisplayName matches the Design.sketch row names, in zone order")
    func s12DisplayNameMatchesSketchRowNames() {
        let names = HeartRateZone.allCases.map(\.s12DisplayName)
        #expect(names == ["Recovery/Light", "Endurance", "Aerobic", "Threshold", "Anaerobic"])
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
