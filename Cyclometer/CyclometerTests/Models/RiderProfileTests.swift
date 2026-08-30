import Testing
import Foundation
import ComposableArchitecture
@testable import Cyclometer

@Suite("RiderProfile")
struct RiderProfileTests {

    // MARK: - Resolution

    @Test("An empty profile resolves to the defaults")
    func emptyProfileResolvesToDefaults() {
        let profile = RiderProfile()

        #expect(profile.restingOverrideBPM == nil)
        #expect(profile.maxOverrideBPM == nil)
        #expect(profile.resolvedRestingBPM() == 60)
        #expect(profile.resolvedMaxBPM() == 190)
    }

    /// The point of the override model: a rider with a Watch and no opinion stores
    /// nothing, so a Health value reaches the zones with no local copy to re-sync.
    @Test("A HealthKit value beats the default when no override is set")
    func healthValueBeatsDefault() {
        let profile = RiderProfile()

        #expect(profile.resolvedRestingBPM(healthResting: 48) == 48)
        #expect(profile.resolvedMaxBPM(healthMax: 178) == 178)
    }

    @Test("An override beats a HealthKit value")
    func overrideBeatsHealthValue() {
        let profile = RiderProfile(restingOverrideBPM: 52, maxOverrideBPM: 185)

        #expect(profile.resolvedRestingBPM(healthResting: 48) == 52)
        #expect(profile.resolvedMaxBPM(healthMax: 178) == 185)
    }

    /// Each field resolves independently — overriding max must not drag resting off
    /// Health, which is the whole reason they are two optionals rather than one
    /// "manual entry" flag.
    @Test("Overriding one field leaves the other on its HealthKit value")
    func fieldsResolveIndependently() {
        let profile = RiderProfile(restingOverrideBPM: nil, maxOverrideBPM: 200)

        #expect(profile.resolvedRestingBPM(healthResting: 48) == 48)
        #expect(profile.resolvedMaxBPM(healthMax: 178) == 200)
    }

    @Test("hrReserve is the resolved max less the resolved resting")
    func hrReserveUsesResolvedValues() {
        #expect(RiderProfile().hrReserve() == 130)
        #expect(RiderProfile(restingOverrideBPM: 50, maxOverrideBPM: 200).hrReserve() == 150)
    }

    // MARK: - Age-based max HR estimate

    @Test("220 minus age, for a birthday already reached this year")
    func estimatedMaxBPMForBirthdayAlreadyReached() {
        let dob = DateComponents(year: 1990, month: 1, day: 1)
        let reference = DateComponents(calendar: .init(identifier: .gregorian), year: 2026, month: 8, day: 30).date!
        // Turned 36 back in January; 220 − 36 = 184.
        #expect(RiderProfile.estimatedMaxBPM(fromDateOfBirth: dob, on: reference) == 184)
    }

    @Test("Age rounds down when this year's birthday has not happened yet")
    func estimatedMaxBPMForBirthdayNotYetReached() {
        let dob = DateComponents(year: 1990, month: 12, day: 25)
        let reference = DateComponents(calendar: .init(identifier: .gregorian), year: 2026, month: 8, day: 30).date!
        // Still 35 until December; 220 − 35 = 185, not 184.
        #expect(RiderProfile.estimatedMaxBPM(fromDateOfBirth: dob, on: reference) == 185)
    }

    @Test("No date of birth on file yields no estimate")
    func estimatedMaxBPMWithNoDateOfBirth() {
        #expect(RiderProfile.estimatedMaxBPM(fromDateOfBirth: nil, on: Date()) == nil)
    }

    // MARK: - Validation

    @Test("A resting override inside the bounds is applied")
    func restingOverrideWithinBounds() throws {
        let updated = try RiderProfile().settingRestingOverride(45)
        #expect(updated.restingOverrideBPM == 45)
    }

    @Test(
        "A resting override outside the bounds is rejected at either edge",
        arguments: [29, 101]
    )
    func restingOverrideOutOfRange(_ bpm: Int) {
        #expect(throws: RiderProfile.ValidationError.restingOutOfRange) {
            try RiderProfile().settingRestingOverride(bpm)
        }
    }

    @Test("The resting bounds are inclusive at both edges", arguments: [30, 100])
    func restingBoundsAreInclusive(_ bpm: Int) throws {
        // A resting of 100 clears the reserve floor only because the default max is
        // 190, leaving 90 — well above minimumHRReserve.
        let updated = try RiderProfile().settingRestingOverride(bpm)
        #expect(updated.restingOverrideBPM == bpm)
    }

    @Test("A max override outside the bounds is rejected at either edge", arguments: [99, 231])
    func maxOverrideOutOfRange(_ bpm: Int) {
        #expect(throws: RiderProfile.ValidationError.maxOutOfRange) {
            try RiderProfile().settingMaxOverride(bpm)
        }
    }

    @Test("The max bounds are inclusive at both edges", arguments: [100, 230])
    func maxBoundsAreInclusive(_ bpm: Int) throws {
        let updated = try RiderProfile().settingMaxOverride(bpm)
        #expect(updated.maxOverrideBPM == bpm)
    }

    /// Individually plausible, jointly nonsense — the case the two range checks
    /// cannot catch on their own.
    @Test("A resting too close to the resolved max is rejected")
    func restingLeavesTooLittleReserve() {
        let profile = RiderProfile(maxOverrideBPM: 100)

        // Equal to the max: no reserve at all.
        #expect(throws: RiderProfile.ValidationError.reserveTooSmall) {
            try profile.settingRestingOverride(100)
        }
        // Inside the resting range and below the max, but only just — five zones
        // cannot fit in a reserve of 5.
        #expect(throws: RiderProfile.ValidationError.reserveTooSmall) {
            try profile.settingRestingOverride(95)
        }
    }

    @Test("A max too close to the resolved resting is rejected")
    func maxLeavesTooLittleReserve() {
        let profile = RiderProfile(restingOverrideBPM: 100)

        #expect(throws: RiderProfile.ValidationError.reserveTooSmall) {
            try profile.settingMaxOverride(100)
        }
        #expect(throws: RiderProfile.ValidationError.reserveTooSmall) {
            try profile.settingMaxOverride(107)
        }
    }

    /// Validation must resolve the *other* field the same way a read will, or the
    /// reserve floor is checked against a value the app never uses — accepting a
    /// profile whose live reserve is below the floor the moment M5 supplies a Health
    /// resting rate.
    @Test("The reserve check honours the HealthKit term the caller reads with")
    func reserveChecksAgainstTheHealthSourcedValue() {
        let profile = RiderProfile()

        // Health says the rider's resting is 100. A max of 105 leaves a live reserve
        // of 5 — rejected. Without the term it would be checked against the default
        // resting of 60, see a reserve of 45, and accept.
        #expect(throws: RiderProfile.ValidationError.reserveTooSmall) {
            try profile.settingMaxOverride(105, healthResting: 100)
        }
        #expect(throws: Never.self) {
            try profile.settingMaxOverride(105)
        }

        // Symmetrically for the resting field against a Health-sourced max.
        #expect(throws: RiderProfile.ValidationError.reserveTooSmall) {
            try profile.settingRestingOverride(100, healthMax: 105)
        }
    }

    /// Rejection is non-destructive; acceptance must be non-destructive about
    /// *everything else*. Copying `self` rather than rebuilding from the memberwise
    /// initialiser is what keeps that true when a field is added later.
    @Test("Setting one override preserves the other")
    func settingOnePreservesTheOther() throws {
        let profile = RiderProfile(restingOverrideBPM: 52, maxOverrideBPM: 185)

        #expect(try profile.settingRestingOverride(48).maxOverrideBPM == 185)
        #expect(try profile.settingMaxOverride(200).restingOverrideBPM == 52)
    }

    /// The reserve floor is exactly the point below which `HeartRateZone.bounds`
    /// stops being the inverse of the forward formula, so it is pinned at its edge
    /// rather than left to drift.
    @Test("The minimum reserve is accepted at its exact edge")
    func minimumReserveIsInclusive() throws {
        let profile = RiderProfile(restingOverrideBPM: 100)
        let updated = try profile.settingMaxOverride(108)

        #expect(updated.hrReserve() == RiderProfile.minimumHRReserve)

        // And every zone still holds at least one bpm at that floor.
        let bounds = HeartRateZone.allCases.map {
            HeartRateZone.bounds(for: $0, maxHR: 108, restingHR: 100)
        }
        #expect(Set(bounds.map(\.lowerBound)).count == 5)
    }

    /// The issue's "rejection is non-destructive" criterion. Returning a new value
    /// rather than mutating means a rejected entry cannot have written anything.
    @Test("A rejected entry leaves the profile untouched")
    func rejectionIsNonDestructive() {
        let profile = RiderProfile(restingOverrideBPM: 52, maxOverrideBPM: 185)

        #expect(throws: RiderProfile.ValidationError.self) {
            try profile.settingRestingOverride(500)
        }
        #expect(throws: RiderProfile.ValidationError.self) {
            try profile.settingMaxOverride(1)
        }
        #expect(profile == RiderProfile(restingOverrideBPM: 52, maxOverrideBPM: 185))
    }

    /// Deferring to Health can never be invalid, so clearing skips the bounds
    /// entirely — including from a state the bounds would now reject.
    @Test("Clearing an override to nil is always allowed")
    func clearingIsAlwaysAllowed() throws {
        let profile = RiderProfile(restingOverrideBPM: 52, maxOverrideBPM: 185)

        let clearedResting = try profile.settingRestingOverride(nil)
        #expect(clearedResting.restingOverrideBPM == nil)
        #expect(clearedResting.maxOverrideBPM == 185)

        let clearedMax = try profile.settingMaxOverride(nil)
        #expect(clearedMax.maxOverrideBPM == nil)
        #expect(clearedMax.restingOverrideBPM == 52)
    }

    // MARK: - Karvonen (DataModel.md §8)

    /// The worked example from §8: resting 60, max 190, HRR 130.
    @Test(
        "Zone boundaries match the §8 worked example",
        arguments: [
            (60, HeartRateZone.zone1), (137, .zone1),
            (138, .zone2), (150, .zone2),
            (151, .zone3), (163, .zone3),
            (164, .zone4), (176, .zone4),
            (177, .zone5), (190, .zone5)
        ]
    )
    func workedExampleBoundaries(_ bpm: Int, _ expected: HeartRateZone) {
        #expect(RiderProfile().zone(forBPM: bpm) == expected)
    }

    @Test("Readings below resting and above max clamp to the end zones")
    func readingsOutsideTheReserve() {
        let profile = RiderProfile()

        #expect(profile.zone(forBPM: 40) == .zone1)
        #expect(profile.zone(forBPM: 0) == .zone1)
        #expect(profile.zone(forBPM: 250) == .zone5)
    }

    /// A non-positive reserve makes the Karvonen quotient undefined. §8 guards it;
    /// this pins the guard so a nonsense profile degrades rather than divides by zero.
    @Test("A non-positive HR reserve resolves to zone 1")
    func nonPositiveReserve() {
        // Not reachable through validation — constructed directly.
        let profile = RiderProfile(restingOverrideBPM: 190, maxOverrideBPM: 190)

        #expect(profile.hrReserve() == 0)
        #expect(profile.zone(forBPM: 190) == .zone1)
    }

    @Test("Zones follow a HealthKit value the rider has not overridden")
    func zonesFollowHealthValues() {
        let profile = RiderProfile()

        // resting 50, max 180 → HRR 130, zone 2 opens at 50 + 78 = 128.
        #expect(profile.zone(forBPM: 127, healthResting: 50, healthMax: 180) == .zone1)
        #expect(profile.zone(forBPM: 128, healthResting: 50, healthMax: 180) == .zone2)
    }

    // MARK: - Zone boundary overrides (#103)

    /// The §8 worked example: resting 60, max 190 — boundaries sit one bpm below
    /// each zone's start.
    @Test(
        "Untouched boundaries match the §8 worked example",
        arguments: [
            (HeartRateZone.zone1, 137), (.zone2, 150), (.zone3, 163), (.zone4, 176)
        ]
    )
    func untouchedBoundariesMatchWorkedExample(_ zone: HeartRateZone, _ expected: Int) {
        #expect(RiderProfile().resolvedBoundaryBPM(afterZone: zone) == expected)
    }

    @Test("There is no boundary after zone 5")
    func noBoundaryAfterZone5() {
        #expect(RiderProfile().resolvedBoundaryBPM(afterZone: .zone5) == nil)
    }

    /// There is nothing valid to set after zone 5 — this must reject rather than
    /// force-unwrap the (nonexistent) next zone, for any caller beyond the one
    /// guarded call site the S12 reducer has today.
    @Test("Setting a boundary after zone 5 is rejected rather than trapping")
    func settingBoundaryAfterZone5IsRejected() {
        #expect(throws: RiderProfile.ValidationError.boundaryOutOfOrder) {
            try RiderProfile().settingBoundaryOverride(200, afterZone: .zone5)
        }
    }

    @Test("Setting a boundary override is applied and read back")
    func settingBoundaryOverrideIsApplied() throws {
        let updated = try RiderProfile().settingBoundaryOverride(140, afterZone: .zone1)

        #expect(updated.zone1CeilingOverrideBPM == 140)
        #expect(updated.resolvedBoundaryBPM(afterZone: .zone1) == 140)
    }

    /// A boundary that would cross its live neighbour makes a gap or overlap
    /// representable, so it is rejected rather than clamped silently.
    @Test("A boundary set at or beyond a neighbouring boundary is rejected")
    func boundaryOutOfOrderIsRejected() {
        let profile = RiderProfile()  // zone1|zone2 boundary at 137, zone2|zone3 at 150

        #expect(throws: RiderProfile.ValidationError.boundaryOutOfOrder) {
            try profile.settingBoundaryOverride(150, afterZone: .zone1)
        }
        #expect(throws: RiderProfile.ValidationError.boundaryOutOfOrder) {
            try profile.settingBoundaryOverride(151, afterZone: .zone1)
        }
    }

    @Test("A boundary set at or below resting is rejected")
    func zone1BoundaryCannotReachResting() {
        let profile = RiderProfile()

        #expect(throws: RiderProfile.ValidationError.boundaryOutOfOrder) {
            try profile.settingBoundaryOverride(60, afterZone: .zone1)
        }
    }

    @Test("A boundary set at or above max is rejected")
    func zone4BoundaryCannotReachMax() {
        let profile = RiderProfile()

        #expect(throws: RiderProfile.ValidationError.boundaryOutOfOrder) {
            try profile.settingBoundaryOverride(190, afterZone: .zone4)
        }
    }

    @Test("Clearing a boundary override defers back to the Karvonen value")
    func clearingBoundaryDefersToKarvonen() throws {
        let profile = try RiderProfile().settingBoundaryOverride(140, afterZone: .zone1)
        let cleared = try profile.settingBoundaryOverride(nil, afterZone: .zone1)

        #expect(cleared.zone1CeilingOverrideBPM == nil)
        #expect(cleared.resolvedBoundaryBPM(afterZone: .zone1) == 137)
    }

    /// The point of pinning: a boundary the rider touched must not silently
    /// re-derive the next time resting or max HR changes, while an untouched
    /// neighbour keeps tracking the live value.
    @Test("A pinned boundary holds its bpm across a max HR change; an unpinned one still recomputes")
    func pinnedBoundarySurvivesMaxChange() throws {
        let profile = try RiderProfile().settingBoundaryOverride(140, afterZone: .zone1)

        #expect(profile.resolvedBoundaryBPM(afterZone: .zone1, healthMax: 220) == 140)
        // zone2's boundary is untouched — it still tracks the new max.
        let defaultAt220 = RiderProfile().resolvedBoundaryBPM(afterZone: .zone2, healthMax: 220)
        #expect(profile.resolvedBoundaryBPM(afterZone: .zone2, healthMax: 220) == defaultAt220)
    }

    @Test("Resetting zone boundaries clears all four and leaves resting/max untouched")
    func resettingClearsAllFourBoundaries() throws {
        var profile = RiderProfile(restingOverrideBPM: 50, maxOverrideBPM: 200)
        profile = try profile.settingBoundaryOverride(130, afterZone: .zone1)
        profile = try profile.settingBoundaryOverride(150, afterZone: .zone2)
        profile = try profile.settingBoundaryOverride(170, afterZone: .zone3)
        profile = try profile.settingBoundaryOverride(190, afterZone: .zone4)

        let reset = profile.resettingZoneBoundaries()

        #expect(reset.zone1CeilingOverrideBPM == nil)
        #expect(reset.zone2CeilingOverrideBPM == nil)
        #expect(reset.zone3CeilingOverrideBPM == nil)
        #expect(reset.zone4CeilingOverrideBPM == nil)
        #expect(reset.restingOverrideBPM == 50)
        #expect(reset.maxOverrideBPM == 200)
    }

    @Test("bounds(for:) matches HeartRateZone.bounds when nothing is overridden")
    func boundsMatchesHeartRateZoneWhenUnoverridden() {
        let profile = RiderProfile()

        for zone in HeartRateZone.allCases {
            #expect(profile.bounds(for: zone) == HeartRateZone.bounds(for: zone, maxHR: 190, restingHR: 60))
        }
    }

    /// A manual boundary shows up on both sides of the shared edge — the "editing
    /// a boundary adjusts the neighbouring band" acceptance criterion.
    @Test("bounds(for:) reflects a manual boundary on both sides of the shared edge")
    func boundsReflectsManualBoundaryOnBothSides() throws {
        let profile = try RiderProfile().settingBoundaryOverride(145, afterZone: .zone2)

        #expect(profile.bounds(for: .zone2).upperBound == 145)
        #expect(profile.bounds(for: .zone3).lowerBound == 146)
    }

    /// `settingRestingOverride`/`settingMaxOverride` don't know about the boundary
    /// overrides this PR adds, so nothing today stops a live resting/max value
    /// from passing a previously pinned boundary. `bounds(for:)` must degrade to a
    /// 1-bpm range rather than build an invalid (lower > upper) `ClosedRange`.
    @Test("bounds(for:) degrades instead of trapping when a live resting value passes a pinned boundary")
    func boundsClampsWhenAPinnedBoundaryIsPassedByALiveValue() throws {
        let profile = try RiderProfile().settingBoundaryOverride(140, afterZone: .zone1)

        let bounds = profile.bounds(for: .zone1, healthResting: 145)

        #expect(bounds.lowerBound <= bounds.upperBound)
    }

    @Test("A document missing the boundary keys decodes with them nil")
    func decodingIsLenientAboutMissingBoundaryKeys() throws {
        let onlyResting = Data(#"{"restingOverrideBPM": 48}"#.utf8)
        let decoded = try JSONDecoder().decode(RiderProfile.self, from: onlyResting)

        #expect(decoded.zone1CeilingOverrideBPM == nil)
        #expect(decoded.zone2CeilingOverrideBPM == nil)
        #expect(decoded.zone3CeilingOverrideBPM == nil)
        #expect(decoded.zone4CeilingOverrideBPM == nil)
    }

    @Test("A profile with boundary overrides round-trips through JSON")
    func boundaryOverridesRoundTripThroughJSON() throws {
        let profile = RiderProfile(
            restingOverrideBPM: 48,
            maxOverrideBPM: 200,
            zone1CeilingOverrideBPM: 120,
            zone2CeilingOverrideBPM: 140,
            zone3CeilingOverrideBPM: 160,
            zone4CeilingOverrideBPM: 180
        )
        let data = try JSONEncoder().encode(profile)

        #expect(try JSONDecoder().decode(RiderProfile.self, from: data) == profile)
    }

    // MARK: - Persistence

    /// Storage is quarantined per test with `FileStorage.inMemory`, the idiom
    /// SettingsFeatureTests uses, so a written override cannot leak between runs.
    @Test("An override survives a re-read of the shared key")
    func overridePersists() {
        let storage = FileStorage.inMemory

        withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.riderProfile) var profile
            $profile.withLock { $0 = RiderProfile(restingOverrideBPM: 48, maxOverrideBPM: 200) }
        }

        withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.riderProfile) var reread
            #expect(reread.restingOverrideBPM == 48)
            #expect(reread.maxOverrideBPM == 200)
            #expect(reread.resolvedMaxBPM() == 200)
        }
    }

    @Test("An untouched profile is empty, so nothing is persisted for a rider with no opinion")
    func untouchedProfileIsEmpty() {
        withDependencies {
            $0.defaultFileStorage = FileStorage.inMemory
        } operation: {
            @Shared(.riderProfile) var profile
            #expect(profile == RiderProfile())
        }
    }

    // MARK: - Decoding leniency (DataModel.md §9)

    /// The rule the hand-written `init(from:)` exists to satisfy: a document written
    /// before a field existed must decode with every *other* field intact. The
    /// synthesised initialiser throws `keyNotFound` here, `.fileStorage` swallows it,
    /// and the rider silently loses the rest of the document.
    @Test("A document missing a key decodes with the other field intact")
    func decodingIsLenientAboutMissingKeys() throws {
        let onlyMax = Data(#"{"maxOverrideBPM":  200}"#.utf8)
        let decoded = try JSONDecoder().decode(RiderProfile.self, from: onlyMax)

        #expect(decoded.maxOverrideBPM == 200)
        #expect(decoded.restingOverrideBPM == nil)
    }

    @Test("An empty document decodes to an empty profile")
    func emptyDocumentDecodes() throws {
        let decoded = try JSONDecoder().decode(RiderProfile.self, from: Data("{}".utf8))
        #expect(decoded == RiderProfile())
    }

    /// The same rule, for a key the app can see but not read. `decodeIfPresent` is
    /// lenient about a missing key but throws on a type mismatch, which would fail
    /// the whole decode and lose the sibling field — so leniency is applied per field.
    @Test("A field of the wrong type falls back without taking the document with it")
    func typeMismatchIsPerField() throws {
        let wrongType = Data(#"{"restingOverrideBPM": "forty-eight", "maxOverrideBPM": 200}"#.utf8)
        let decoded = try JSONDecoder().decode(RiderProfile.self, from: wrongType)

        #expect(decoded.restingOverrideBPM == nil)
        #expect(decoded.maxOverrideBPM == 200)
    }

    /// Leniency, not strictness — §9's rule for a key the app no longer knows.
    @Test("An unrecognised key is ignored rather than failing the decode")
    func unrecognisedKeyIsIgnored() throws {
        let withExtra = Data(#"{"restingOverrideBPM": 48, "dateOfBirth": 12345}"#.utf8)
        let decoded = try JSONDecoder().decode(RiderProfile.self, from: withExtra)

        #expect(decoded.restingOverrideBPM == 48)
    }

    /// An explicit null and an absent key both mean "defer to Health" — the
    /// double-optional flattening in `init(from:)`.
    @Test("An explicit null decodes as no override")
    func explicitNullDecodesAsNoOverride() throws {
        let withNull = Data(#"{"restingOverrideBPM": null, "maxOverrideBPM": 200}"#.utf8)
        let decoded = try JSONDecoder().decode(RiderProfile.self, from: withNull)

        #expect(decoded.restingOverrideBPM == nil)
        #expect(decoded.maxOverrideBPM == 200)
    }

    @Test("A profile round-trips through JSON")
    func roundTripsThroughJSON() throws {
        let profile = RiderProfile(restingOverrideBPM: 48, maxOverrideBPM: 200)
        let data = try JSONEncoder().encode(profile)

        #expect(try JSONDecoder().decode(RiderProfile.self, from: data) == profile)
    }
}
