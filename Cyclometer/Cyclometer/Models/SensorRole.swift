import Foundation

/// The role a BLE peripheral fills — the persisted lookup key behind every
/// `PairedSensor` record (DataModel.md §3.7).
///
/// Speed and cadence are separate roles even when one physical CSC device serves
/// both, so a combo sensor assigned Both is two records sharing a `peripheralID`.
///
/// Lived inside `BLECSCClient` until #93, when radar and heart rate joined the same
/// Sensors screen and the enum stopped being CSC property.
///
/// Declaration order is load-bearing — `allCases` drives the S11 row subtitle and the
/// order records are written to the preferences file — and follows DataModel.md §3.7's
/// device-list order rather than alphabetical.
///
/// `power` is reserved for Phase 3 and deliberately absent rather than declared: a case
/// no hardware can fill would still surface in `allCases` and in every exhaustive
/// switch. Adding it later needs no migration (DataModel.md §9).
enum SensorRole: String, Codable, Hashable, CaseIterable, Sendable {
    case radar
    case heartRate
    case speed      // CSC profile — wheel revolution data
    case cadence    // CSC profile — crank revolution data

    /// The roles `BLECSCClient` can fill. `AppPreferences.cscAssignments` filters on
    /// this so the CSC client is never handed a radar or HR peripheral to connect to.
    static let cscRoles: Set<SensorRole> = [.speed, .cadence]

    var displayName: String {
        switch self {
        case .radar:     "Radar"
        case .heartRate: "Heart Rate"
        case .speed:     "Speed"
        case .cadence:   "Cadence"
        }
    }
}
