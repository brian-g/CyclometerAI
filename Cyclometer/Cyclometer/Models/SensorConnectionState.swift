import Foundation

/// The BLE connection lifecycle of one peripheral, per BLE.md §6. `.active` means
/// notifications are enabled and measurement data is flowing.
///
/// One enum for all three clients. `BLECSCClient` and `VariaRadarClient` each declared
/// a character-identical copy, and `DiscoveredDevice` — which now carries rows from
/// both — could not have referred to either without picking a winner. Both keep a
/// `typealias ConnectionState` so their own call sites and streams read unchanged.
///
/// `BLEHRClient` never had one; it tracks a target and a notifying flag and projects
/// them onto these cases at the discovery boundary.
enum SensorConnectionState: Equatable, Sendable {
    case disconnected
    case scanning
    case connecting
    case connected
    case active
    case reconnecting
}
