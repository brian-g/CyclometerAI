import Foundation

/// What a discovered peripheral advertises itself as — the service-type tag on every
/// row of the Sensors screen (S11).
///
/// Distinct from `SensorRole`, and the distinction is the whole point. A kind is what
/// the hardware *is*, read off its advertised service UUID and known the moment it is
/// discovered. A role is what the rider has *decided it does*, which for a CSC combo
/// sensor isn't known until 0x2A5C has been read and the role prompt answered
/// (BLE.md §5.0). Speed and cadence are two roles behind one kind for exactly that
/// reason.
///
/// `Set<SensorKind>` rather than a single value on `DiscoveredDevice`: one peripheral
/// can advertise more than one supported service, and unified discovery merges the
/// three client streams into one row per `CBPeripheral.identifier` (#98).
///
/// The UUID each case maps to lives in `Clients/BLE/BLEServiceUUIDs.swift`, so this
/// stays free of CoreBluetooth.
enum SensorKind: String, Hashable, CaseIterable, Sendable {
    case radar
    case heartRate
    case speedCadence

    /// The kind of hardware that fills `role`, or nil when no MVP profile does.
    ///
    /// Used to tag a row synthesised from a `PairedSensor` record when the device is
    /// out of range and no advertisement is available to classify it. `.power` returns
    /// nil: the role is declared (Phase 3 owns the hardware) but nothing scans for
    /// 0x1818 yet, so claiming a kind for it would invent a row the app cannot fill.
    init?(role: SensorRole) {
        switch role {
        case .radar:            self = .radar
        case .heartRate:        self = .heartRate
        case .speed, .cadence:  self = .speedCadence
        case .power:            return nil
        }
    }
}
