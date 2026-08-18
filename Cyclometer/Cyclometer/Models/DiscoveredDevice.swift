import Foundation

/// One BLE peripheral seen during this scan session, for the pairing UI (S11 subset).
///
/// Shared by `VariaRadarClient` and `BLEHRClient`, which each fill exactly one role and
/// so have identical rows to report. `BLECSCClient.DiscoveredSensor` stays separate
/// until #98 merges all three streams — its extra fields (roles, capabilities) are
/// meaningless here, and the service-type tag #98 needs carries no information at the
/// source, where a radar stream contains only radars.
///
/// No RSSI: UX.md §S11 resolves "RSSI display: none", and the transport discards the
/// value at the `.discovered` handler. No battery and no connection detail beyond
/// `isConnected` — the row that renders them is #100's.
struct DiscoveredDevice: Equatable, Sendable, Identifiable {
    /// `CBPeripheral.identifier` — stable per device per iOS install.
    let id: UUID
    /// Advertised name, or nil if the peripheral didn't advertise one.
    let name: String?
    /// Matches the gate this client was pushed via `setPairedSensor`.
    ///
    /// Note this means something different from `BLECSCClient.DiscoveredSensor.isPaired`,
    /// which is live role tenancy. Here it is the rider's durable choice as the client
    /// knows it, so a paired device that is out of range still reads `true` — but only
    /// once it has been seen this session, since an unseen device produces no row at
    /// all. The Sensors screen builds its Paired section from `AppPreferences.pairedSensors`
    /// for exactly that reason. #98 reconciles the two meanings.
    let isPaired: Bool
    /// A live connection is held right now.
    let isConnected: Bool
}
