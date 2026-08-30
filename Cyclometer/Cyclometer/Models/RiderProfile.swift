import ComposableArchitecture
import Foundation

/// The rider's physiological inputs to the Karvonen zone calculation
/// (DataModel.md §3.5, §8).
///
/// **This stores overrides, not values.** Resting heart rate and date of birth are
/// HealthKit's to own — `HKQuantityTypeIdentifier.restingHeartRate` is rewritten
/// daily by an Apple Watch, and an app-owned copy would go stale the first time the
/// rider's fitness changed. So a field here is `nil` until the rider disagrees with
/// what Health says, or Health cannot answer at all. A rider wearing a Watch who
/// never opens Settings persists nothing.
///
/// Max heart rate is the exception that makes this type necessary rather than
/// redundant: **HealthKit has no max-heart-rate type.** The closest available
/// reading is `.discreteMax` over historical `heartRate` samples, which is *highest
/// ever observed* — a number that means nothing for a rider who has never gone near
/// their limit wearing a watch. PRD §9.4 falls back to 220 − age for exactly this
/// reason, and UX.md §S12 keeps manual entry as the fallback "when Health is denied
/// or empty".
///
/// Resolution happens at read time — `override ?? healthKit ?? default` — so zone
/// boundaries follow a Health value the moment it changes, with no local copy to
/// re-sync. M5 supplies the middle term; until then it is always absent.
///
/// Stored as a JSON document rather than a SwiftData `@Model` for the reason §3.6
/// records for `AppPreferences`: exactly one record exists, so there is nothing to
/// `@Query`, and a `@Model` would put an async load in front of the Settings screen.
struct RiderProfile: Codable, Equatable, Sendable {

    /// Resting heart rate the rider entered by hand, or `nil` to defer to Health.
    var restingOverrideBPM: Int?

    /// Max heart rate the rider entered by hand, or `nil` to defer.
    ///
    /// In practice this is the field that gets set: Health has no value to defer to
    /// (see the type note), so anything better than the default arrives this way
    /// until M5 can offer a 220 − age estimate.
    var maxOverrideBPM: Int?

    /// The bpm at which Recovery/Light ends and Endurance begins, or `nil` to defer
    /// to the Karvonen-derived value. Set by the S12 HR Zones section's first
    /// `Stepper` (#103); stays pinned across a resting/max change until reset.
    var zone1CeilingOverrideBPM: Int?

    /// The bpm at which Endurance ends and Aerobic begins. See
    /// `zone1CeilingOverrideBPM`.
    var zone2CeilingOverrideBPM: Int?

    /// The bpm at which Aerobic ends and Threshold begins. See
    /// `zone1CeilingOverrideBPM`.
    var zone3CeilingOverrideBPM: Int?

    /// The bpm at which Threshold ends and Anaerobic begins. See
    /// `zone1CeilingOverrideBPM`.
    var zone4CeilingOverrideBPM: Int?

    init(
        restingOverrideBPM: Int? = nil,
        maxOverrideBPM: Int? = nil,
        zone1CeilingOverrideBPM: Int? = nil,
        zone2CeilingOverrideBPM: Int? = nil,
        zone3CeilingOverrideBPM: Int? = nil,
        zone4CeilingOverrideBPM: Int? = nil
    ) {
        self.restingOverrideBPM = restingOverrideBPM
        self.maxOverrideBPM = maxOverrideBPM
        self.zone1CeilingOverrideBPM = zone1CeilingOverrideBPM
        self.zone2CeilingOverrideBPM = zone2CeilingOverrideBPM
        self.zone3CeilingOverrideBPM = zone3CeilingOverrideBPM
        self.zone4CeilingOverrideBPM = zone4CeilingOverrideBPM
    }

    /// Written by hand for the reason DataModel.md §9 gives: the synthesised
    /// `init(from:)` throws `keyNotFound` rather than falling back to a property's
    /// default, `.fileStorage` swallows that and hands back a fresh value, and the
    /// rider silently loses every *other* field in the document. `decodeIfPresent`
    /// per field is what makes adding one free.
    ///
    /// The double-optional flattening is deliberate: a key that is absent and a key
    /// explicitly written as `null` both mean "no override".
    ///
    /// `try?` per field, not `try`: `decodeIfPresent` is lenient about a *missing*
    /// key but still throws on a type mismatch, which would fail the whole decode
    /// and lose the other field — the exact outcome this initialiser exists to
    /// prevent. A field the app cannot read falls back to "no override" on its own.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        restingOverrideBPM = (try? container.decodeIfPresent(
            Int?.self, forKey: .restingOverrideBPM
        )) ?? nil
        maxOverrideBPM = (try? container.decodeIfPresent(
            Int?.self, forKey: .maxOverrideBPM
        )) ?? nil
        zone1CeilingOverrideBPM = (try? container.decodeIfPresent(
            Int?.self, forKey: .zone1CeilingOverrideBPM
        )) ?? nil
        zone2CeilingOverrideBPM = (try? container.decodeIfPresent(
            Int?.self, forKey: .zone2CeilingOverrideBPM
        )) ?? nil
        zone3CeilingOverrideBPM = (try? container.decodeIfPresent(
            Int?.self, forKey: .zone3CeilingOverrideBPM
        )) ?? nil
        zone4CeilingOverrideBPM = (try? container.decodeIfPresent(
            Int?.self, forKey: .zone4CeilingOverrideBPM
        )) ?? nil
    }
}

// MARK: - Resolution

extension RiderProfile {

    /// Used when neither the rider nor Health has supplied a resting heart rate.
    /// Matches the value DataModel.md §3.5 has always specified.
    static let defaultRestingBPM = 60

    /// Used when neither the rider nor Health has supplied a max heart rate — the
    /// 220 − age estimate for a 30-year-old, and the value §3.5 specifies.
    static let defaultMaxBPM = 190

    /// `override ?? healthKit ?? default`.
    ///
    /// `healthResting` defaults to `nil` because no HealthKit read exists yet — M5
    /// passes the real value in without this resolver changing shape.
    func resolvedRestingBPM(healthResting: Int? = nil) -> Int {
        restingOverrideBPM ?? healthResting ?? Self.defaultRestingBPM
    }

    /// `override ?? estimate ?? default`. M5 passes the 220 − age estimate as
    /// `healthMax`; there is no HealthKit max-HR type to read directly.
    func resolvedMaxBPM(healthMax: Int? = nil) -> Int {
        maxOverrideBPM ?? healthMax ?? Self.defaultMaxBPM
    }

    /// PRD §9.4's 220 − age estimate, computed from the HealthKit `dateOfBirth`
    /// characteristic. `nil` when the rider has none on file — the same "nothing to
    /// offer" case `HealthKitClient.fetchDateOfBirth` already collapses denial and
    /// absence into.
    ///
    /// `.gregorian` explicitly rather than `.current` — `dateOfBirthComponents()` is
    /// a Gregorian characteristic, and the estimate must not vary with the device's
    /// calendar locale. `referenceDate` is required rather than defaulted to `Date()`
    /// so callers supply it from `@Dependency(\.date)`, keeping this testable.
    static func estimatedMaxBPM(fromDateOfBirth dateOfBirth: DateComponents?, on referenceDate: Date) -> Int? {
        guard let dateOfBirth,
              let birthDate = Calendar(identifier: .gregorian).date(from: dateOfBirth),
              let age = Calendar(identifier: .gregorian).dateComponents([.year], from: birthDate, to: referenceDate).year
        else { return nil }
        return 220 - age
    }

    /// The rider's heart-rate reserve — the denominator of the Karvonen formula
    /// (DataModel.md §8).
    func hrReserve(healthResting: Int? = nil, healthMax: Int? = nil) -> Int {
        resolvedMaxBPM(healthMax: healthMax) - resolvedRestingBPM(healthResting: healthResting)
    }

    /// The Karvonen zone for a live reading, against the resolved profile.
    /// Delegates to `HeartRateZone` rather than restating §8's formula.
    func zone(forBPM bpm: Int, healthResting: Int? = nil, healthMax: Int? = nil) -> HeartRateZone {
        HeartRateZone.zone(
            bpm: bpm,
            maxHR: resolvedMaxBPM(healthMax: healthMax),
            restingHR: resolvedRestingBPM(healthResting: healthResting)
        )
    }
}

// MARK: - Zone boundary overrides (#103)

extension RiderProfile {

    private func boundaryOverride(afterZone zone: HeartRateZone) -> Int? {
        switch zone {
        case .zone1: zone1CeilingOverrideBPM
        case .zone2: zone2CeilingOverrideBPM
        case .zone3: zone3CeilingOverrideBPM
        case .zone4: zone4CeilingOverrideBPM
        case .zone5: nil
        }
    }

    private mutating func setBoundaryOverride(_ bpm: Int?, afterZone zone: HeartRateZone) {
        switch zone {
        case .zone1: zone1CeilingOverrideBPM = bpm
        case .zone2: zone2CeilingOverrideBPM = bpm
        case .zone3: zone3CeilingOverrideBPM = bpm
        case .zone4: zone4CeilingOverrideBPM = bpm
        case .zone5: break
        }
    }

    /// The resolved bpm of the boundary between `zone` and the next one —
    /// `override ?? karvonenDefault`, the same precedence as resting/max, so a
    /// boundary the rider has never touched keeps tracking a Health-driven resting
    /// or max HR the instant either changes. `nil` for `.zone5`, which has no
    /// boundary after it inside the table.
    func resolvedBoundaryBPM(
        afterZone zone: HeartRateZone,
        healthResting: Int? = nil,
        healthMax: Int? = nil
    ) -> Int? {
        guard let next = HeartRateZone(rawValue: zone.rawValue + 1) else { return nil }
        let karvonenDefault = HeartRateZone.lowerBoundBPM(
            for: next,
            maxHR: resolvedMaxBPM(healthMax: healthMax),
            restingHR: resolvedRestingBPM(healthResting: healthResting)
        ) - 1
        return boundaryOverride(afterZone: zone) ?? karvonenDefault
    }

    /// The bpm range `zone` displays in the S12 HR Zones table — Karvonen by
    /// default, clamped around any boundary the rider has manually stepped.
    ///
    /// Distinct from `HeartRateZone.bounds(for:maxHR:restingHR:)`, which has no
    /// concept of an override and keeps serving any other live-zone display in the
    /// app exactly as before.
    func bounds(for zone: HeartRateZone, healthResting: Int? = nil, healthMax: Int? = nil) -> ClosedRange<Int> {
        let lower: Int
        if let previous = HeartRateZone(rawValue: zone.rawValue - 1) {
            lower = resolvedBoundaryBPM(afterZone: previous, healthResting: healthResting, healthMax: healthMax)! + 1
        } else {
            lower = resolvedRestingBPM(healthResting: healthResting)
        }
        let upper = resolvedBoundaryBPM(afterZone: zone, healthResting: healthResting, healthMax: healthMax)
            ?? resolvedMaxBPM(healthMax: healthMax)
        // `max` only bites when a boundary pinned before a resting/max change no
        // longer clears its neighbour — `settingRestingOverride`/`settingMaxOverride`
        // don't know about these overrides, so nothing rejects that combination
        // today. Same guard `HeartRateZone.bounds` uses for the analogous case.
        return lower...max(lower, upper)
    }

    /// A copy with the boundary after `zone` (`.zone1`...`.zone4`) set to `bpm`, or
    /// a thrown reason and no change. `nil` clears the override and is always
    /// allowed.
    ///
    /// Clamped strictly between its live neighbouring boundaries — or resting/max
    /// at the table's outer edges — so every zone keeps at least 1 bpm and no gap
    /// or overlap ever becomes representable, the #103 acceptance criterion.
    func settingBoundaryOverride(
        _ bpm: Int?,
        afterZone zone: HeartRateZone,
        healthResting: Int? = nil,
        healthMax: Int? = nil
    ) throws(ValidationError) -> RiderProfile {
        var copy = self
        guard let bpm else {
            copy.setBoundaryOverride(nil, afterZone: zone)
            return copy
        }
        // There is no boundary after zone 5 — a caller passing it has nothing
        // valid to set. Rejecting here, rather than force-unwrapping the `next`
        // zone below, is what keeps this safe for any future caller beyond the
        // one guarded call site the S12 reducer has today.
        guard zone != .zone5 else { throw .boundaryOutOfOrder }
        let lowerNeighbor: Int
        if let previous = HeartRateZone(rawValue: zone.rawValue - 1) {
            lowerNeighbor = resolvedBoundaryBPM(afterZone: previous, healthResting: healthResting, healthMax: healthMax)!
        } else {
            lowerNeighbor = resolvedRestingBPM(healthResting: healthResting)
        }
        let upperNeighbor: Int
        if zone == .zone4 {
            upperNeighbor = resolvedMaxBPM(healthMax: healthMax)
        } else {
            let next = HeartRateZone(rawValue: zone.rawValue + 1)!
            upperNeighbor = resolvedBoundaryBPM(afterZone: next, healthResting: healthResting, healthMax: healthMax)!
        }
        guard bpm > lowerNeighbor, bpm < upperNeighbor else { throw .boundaryOutOfOrder }
        copy.setBoundaryOverride(bpm, afterZone: zone)
        return copy
    }

    /// Clears all 4 boundary overrides — the S12 "Reset HR Zones to Defaults" row.
    /// Leaves `restingOverrideBPM`/`maxOverrideBPM` untouched; those are a separate
    /// concern with no S12 entry point yet.
    func resettingZoneBoundaries() -> RiderProfile {
        var copy = self
        for zone in [HeartRateZone.zone1, .zone2, .zone3, .zone4] {
            copy.setBoundaryOverride(nil, afterZone: zone)
        }
        return copy
    }
}

// MARK: - Validation

extension RiderProfile {

    /// Sanity bounds for manual entry, in the spirit of `WheelPreset.validRange`.
    /// Elite endurance athletes reach the low 30s at rest; anything above 100 is
    /// tachycardic and not a resting rate.
    static let restingValidRange = 30...100

    /// Junior riders record maxima above 200, and 220 − age tops out around 220 for
    /// a small child, so the ceiling is deliberately generous.
    static let maxValidRange = 100...230

    /// The smallest heart-rate reserve that still describes five distinct zones.
    ///
    /// Derived, not guessed: the Karvonen bands are 10% of reserve wide, so below a
    /// reserve of 8 the rounding collapses two or more zone boundaries onto the same
    /// bpm and a band exists with no bpm of its own. `HeartRateZone.bounds` would
    /// then hand back a range for a zone no reading can fall in. Rejecting the
    /// profile is what keeps the zone table meaningful and keeps `bounds` the exact
    /// inverse of `HeartRateZone.zone(bpm:maxHR:restingHR:)`.
    ///
    /// It subsumes "resting must be below max" — a reserve of 0 or less fails it too.
    static let minimumHRReserve = 8

    enum ValidationError: Error, Equatable {
        case restingOutOfRange
        case maxOutOfRange
        /// Both values are individually plausible but incoherent together — a
        /// resting of 95 against a max of 100 passes both ranges and still leaves
        /// no room for five zones.
        case reserveTooSmall
        /// A zone boundary set at or beyond a live neighbouring boundary (or
        /// resting/max at the table's outer edges) — would make a gap or overlap
        /// representable, so it's rejected rather than clamped silently (#103).
        case boundaryOutOfOrder
    }

    /// A copy with the resting override applied, or a thrown reason and no change.
    ///
    /// Returning a new value rather than mutating in place is what makes rejection
    /// non-destructive: a caller that does not get a value back still holds the
    /// profile it started with. It copies `self` rather than rebuilding from the
    /// memberwise initialiser so a field added later survives an HR edit — the same
    /// "adding a field is free" property `init(from:)` gives decoding.
    ///
    /// Passing `nil` clears the override and is always allowed — deferring to Health
    /// cannot be invalid.
    ///
    /// The `health*` terms must be the same ones the caller reads with, or the
    /// reserve floor is checked against a value the app will not use: with a Health
    /// resting of 100 and no override, validating a max of 105 against the *default*
    /// resting of 60 sees a reserve of 45 and accepts, while the live reserve is 5.
    func settingRestingOverride(
        _ bpm: Int?,
        healthMax: Int? = nil
    ) throws(ValidationError) -> RiderProfile {
        var copy = self
        guard let bpm else {
            copy.restingOverrideBPM = nil
            return copy
        }
        guard Self.restingValidRange.contains(bpm) else { throw .restingOutOfRange }
        // Checked against the *resolved* max so the pair is coherent whether or not
        // the rider has overridden the other field.
        guard resolvedMaxBPM(healthMax: healthMax) - bpm >= Self.minimumHRReserve else {
            throw .reserveTooSmall
        }
        copy.restingOverrideBPM = bpm
        return copy
    }

    /// A copy with the max override applied, or a thrown reason and no change.
    /// `nil` clears the override. See `settingRestingOverride` on `health*`.
    func settingMaxOverride(
        _ bpm: Int?,
        healthResting: Int? = nil
    ) throws(ValidationError) -> RiderProfile {
        var copy = self
        guard let bpm else {
            copy.maxOverrideBPM = nil
            return copy
        }
        guard Self.maxValidRange.contains(bpm) else { throw .maxOutOfRange }
        guard bpm - resolvedRestingBPM(healthResting: healthResting) >= Self.minimumHRReserve else {
            throw .reserveTooSmall
        }
        copy.maxOverrideBPM = bpm
        return copy
    }
}

// MARK: - Storage

extension SharedReaderKey where Self == FileStorageKey<RiderProfile>.Default {
    /// Type-safe key so call sites read `@Shared(.riderProfile)` and cannot point
    /// two features at different storage.
    ///
    /// A separate document from `app-preferences.json` because OQDM5 split
    /// physiology from preferences deliberately, and M5's Health read should have
    /// one file to touch.
    static var riderProfile: Self {
        Self[
            .fileStorage(.documentsDirectory.appending(component: "rider-profile.json")),
            default: RiderProfile()
        ]
    }
}
