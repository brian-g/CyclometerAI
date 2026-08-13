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

    /// The sensor filling `role`, or nil when the role is unpaired. Role-keyed rather
    /// than peripheral-keyed because that is how every consumer asks: one sensor per
    /// role, app-wide, for MVP (DataModel.md §3.9 gives roles a bike dimension in
    /// Phase 2).
    func pairedSensor(for role: BLECSCClient.SensorRole) -> PairedSensor? {
        pairedSensors.first { $0.role == role }
    }

    /// The same records grouped the way `BLECSCClient.setPairedSensors` wants them —
    /// one entry per peripheral, so a combo device assigned Both is connected once
    /// holding two roles rather than connected twice.
    var sensorAssignments: [UUID: Set<BLECSCClient.SensorRole>] {
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
