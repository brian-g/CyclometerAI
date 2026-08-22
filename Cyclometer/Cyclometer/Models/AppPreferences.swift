import ComposableArchitecture
import Foundation

/// Persisted, non-physiological rider preferences — the MVP slice of
/// DataModel.md §3.6.
///
/// Stored as a single JSON document rather than a SwiftData `@Model`: exactly one
/// record exists, so there is nothing to query and no relationship worth
/// traversing, and `@Shared` gives synchronous reads instead of an async load in
/// front of every consumer. SwiftData stays reserved for Ride / RadarEvent /
/// TrackPoint, which do need querying.
///
/// Further fields land with the features that consume them.
struct AppPreferences: Codable, Equatable, Sendable {
    /// Wheel rollout in millimetres. Drives the BLE speed and distance
    /// derivation; auto-calibration (#70) writes back here too.
    ///
    /// One global value, which assumes the rider has a single bike. That is an MVP
    /// scoping decision, not the end state — Phase 2 moves this onto the speed-role
    /// PairedSensor, because a hub-mounted CSC sensor is already bound to exactly
    /// one wheel, and bikes own their sensors. See DataModel.md §3.9 and the
    /// research note in PRD §8.9.1.
    var wheelCircumferenceMM: Int = WheelPreset.default.circumferenceMM

    /// Every pairing decision the rider has made, one record per sensor per role
    /// (DataModel.md §3.7). This is the source of truth for which peripherals the app
    /// connects to: `BLECSCClient` adopts nothing on its own, and is told what to
    /// reconnect via `setPairedSensors`.
    ///
    /// An `app-preferences.json` written before this field existed decodes to `[]`,
    /// so an existing install simply starts unpaired.
    var pairedSensors: [PairedSensor] = []

    /// Whether the dashboard dims itself after an idle period (#110, S12). On by
    /// default — a multi-hour ride is the case that needs the battery back, and the
    /// rider can turn it off in Settings.
    ///
    /// Only gates the dim. The wake lock is not a preference: a bicycle computer that
    /// blanks mid-ride is broken, not configurable.
    var isAutoDimEnabled: Bool = true

    /// Speed and distance display units (DataModel.md §3.6). Defaults to the device
    /// locale's measurement system, so a rider who never opens Settings still gets
    /// the units their phone is configured for.
    ///
    /// Nothing reads this yet. `ActiveRideFeature.unitSystem` is still seeded from
    /// `Locale` per-feature and the S12 picker is still a disconnected `String` —
    /// pointing both at this field is #102 and #8.
    var preferredUnit: UnitSystem = .system

    /// Whether the ride recorder pauses itself when the rider stops (PRD §8.8, S12).
    /// On by default, matching the value the S12 toggle has carried since it was
    /// ephemeral feature state.
    ///
    /// Nothing reads this yet: `SettingsFeature` still toggles its own copy, and the
    /// stop detection the ride state machine needs lands with #102.
    var isAutoPauseEnabled: Bool = true

    /// Whether the rider has finished onboarding (S01→S02) at least once (#105). Gates
    /// `AppFeature`'s launch presentation — once true, onboarding never reappears, even
    /// if a permission it once checked is later revoked.
    var hasCompletedOnboarding: Bool = false

    /// Whether the rider has passed the Welcome step specifically, so a relaunch
    /// mid-flow resumes at Sensor Pairing rather than restarting at Welcome (#105).
    /// Meaningless once `hasCompletedOnboarding` is true.
    var hasCompletedWelcomeStep: Bool = false

    /// The sensor filling `role`, or nil when the role is unpaired. Role-keyed rather
    /// than peripheral-keyed because that is how every consumer asks: one sensor per
    /// role, app-wide, for MVP (DataModel.md §3.9 gives roles a bike dimension in
    /// Phase 2).
    func pairedSensor(for role: SensorRole) -> PairedSensor? {
        pairedSensors.first { $0.role == role }
    }

    /// The CSC-role records grouped the way `BLECSCClient.setPairedSensors` wants them
    /// — one entry per peripheral, so a combo device assigned Both is connected once
    /// holding two roles rather than connected twice.
    ///
    /// Filtered to `SensorRole.cscRoles` because the collection is no longer CSC-only:
    /// radar and heart rate records live here too (#93), and handing their peripheral
    /// IDs to the CSC client would have it connect to a radar looking for 0x1816.
    var cscAssignments: [UUID: Set<SensorRole>] {
        Dictionary(grouping: pairedSensors.filter(\.isCSC), by: \.peripheralID)
            .mapValues { Set($0.map(\.role)) }
    }

    /// Peripherals holding at least one CSC role — the membership test the CSC pairing
    /// screen means when it asks whether a device is already paired. A peripheral
    /// paired only for radar or heart rate is *not* in here, so the screen still offers
    /// it a speed or cadence role.
    var cscPairedIDs: Set<UUID> { Set(cscAssignments.keys) }

    /// Every pairing grouped by peripheral, radar and heart rate included — what the
    /// Sensors screen asks now that it lists all three kinds in one list (#98).
    ///
    /// Unfiltered, unlike `cscAssignments`: that one exists to keep non-CSC peripherals
    /// away from a client that only speaks 0x1816, whereas the screen has to show a
    /// paired device whatever profile it serves, including one that is out of range and
    /// so appears on no discovery stream at all.
    var pairedRoles: [UUID: Set<SensorRole>] {
        Dictionary(grouping: pairedSensors, by: \.peripheralID)
            .mapValues { Set($0.map(\.role)) }
    }

    init() {}

    /// Written by hand because the synthesised `init(from:)` does *not* fall back to
    /// a property's default when its key is absent — it throws `keyNotFound`. A
    /// document written before a field was added would fail to decode entirely, and
    /// `.fileStorage` would hand back a fresh `AppPreferences()`, silently resetting
    /// every *other* preference too. Decoding each field with `decodeIfPresent` is
    /// what actually makes "adding a field is free" (DataModel.md §9) true.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        wheelCircumferenceMM = try container.decodeIfPresent(
            Int.self, forKey: .wheelCircumferenceMM
        ) ?? WheelPreset.default.circumferenceMM
        pairedSensors = try container.decodeIfPresent(
            [PairedSensor].self, forKey: .pairedSensors
        ) ?? []
        isAutoDimEnabled = try container.decodeIfPresent(
            Bool.self, forKey: .isAutoDimEnabled
        ) ?? true
        preferredUnit = try container.decodeIfPresent(
            UnitSystem.self, forKey: .preferredUnit
        ) ?? .system
        isAutoPauseEnabled = try container.decodeIfPresent(
            Bool.self, forKey: .isAutoPauseEnabled
        ) ?? true
        hasCompletedOnboarding = try container.decodeIfPresent(
            Bool.self, forKey: .hasCompletedOnboarding
        ) ?? false
        hasCompletedWelcomeStep = try container.decodeIfPresent(
            Bool.self, forKey: .hasCompletedWelcomeStep
        ) ?? false
    }
}

extension SharedReaderKey where Self == FileStorageKey<AppPreferences>.Default {
    /// Type-safe key so call sites read `@Shared(.appPreferences)` and cannot
    /// accidentally point two features at different storage.
    static var appPreferences: Self {
        Self[
            .fileStorage(.documentsDirectory.appending(component: "app-preferences.json")),
            default: AppPreferences()
        ]
    }
}
