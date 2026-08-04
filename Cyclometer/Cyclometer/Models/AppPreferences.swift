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
/// Further fields land with the features that consume them; today only wheel
/// circumference has a consumer (`BLECSCClient.setWheelCircumference`).
struct AppPreferences: Codable, Equatable, Sendable {
    /// Wheel rollout in millimetres. Drives the BLE speed and distance
    /// derivation; auto-calibration (#70) writes back here too.
    ///
    /// One global value, which assumes the rider has one bike with one wheelset.
    /// That is an MVP scoping decision, not the end state — Phase 2 moves this to
    /// a Wheelset owned by a Bike, because a rider owns several bikes and a bike
    /// carries several wheelsets (race vs training, road vs gravel), each with its
    /// own circumference and calibration history. Paired sensors move under Bike
    /// at the same time. See DataModel.md §3.9.
    var wheelCircumferenceMM: Int = WheelPreset.default.circumferenceMM
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
