import Foundation

/// One BLE sensor in one role — the durable record of a rider's pairing decision
/// (DataModel.md §3.7).
///
/// A combo CSC device assigned Both appears twice, same `peripheralID` with
/// different `role` values. That is deliberate: role is the lookup key, so
/// `pairedSensor(for:)` stays a single lookup whether one device or two fill the
/// pair.
///
/// A `Codable` struct rather than the `@Model` §3.7 originally sketched. #69 took
/// AppPreferences out of SwiftData, which left this with no `@Relationship` owner;
/// with three to five records that are never queried, a `@Model` would buy an async
/// load in front of every consumer and nothing else. `peripheralID` is a `UUID`
/// rather than the spec's `peripheralIdentifierString` for the same reason — the
/// string was a SwiftData accommodation, and JSON round-trips `UUID` natively.
struct PairedSensor: Codable, Equatable, Sendable {
    /// `CBPeripheral.identifier` — stable per device per iOS install.
    var peripheralID: UUID
    var role: SensorRole
    /// Advertised name at pairing time. Retained so a paired sensor that is out of
    /// range still has something to show on the Sensors screen, where no live
    /// advertisement is available to name it.
    var displayName: String?

    /// Whether this record is one `BLECSCClient` can act on.
    ///
    /// The Sensors screen is CSC-only until #98 unifies discovery, but the collection
    /// it reads and writes is not: radar and heart rate records live here too (#93).
    /// Every membership test and every removal it performs has to scope itself this
    /// way, or a peripheral serving more than one profile loses its other pairings —
    /// or is hidden from the screen entirely because something else already claimed it.
    var isCSC: Bool { SensorRole.cscRoles.contains(role) }
}
