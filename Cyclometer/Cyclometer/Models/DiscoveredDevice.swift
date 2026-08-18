import Foundation

/// One BLE peripheral seen during this scan session — the row model behind the
/// Sensors screen (S11).
///
/// Emitted by all three clients and merged into one list by `DeviceManagementFeature`
/// (#98). Each client fills the fields it can answer for and leaves the rest nil: a
/// radar knows nothing about 0x2A5C, and `BLEHRClient` has no role to hand out beyond
/// `.heartRate`. `BLECSCClient.DiscoveredSensor` was folded into this type rather than
/// kept alongside it, because a screen showing one flat list cannot hold two row types.
///
/// No RSSI: UX.md §S11 resolves "RSSI display: none", and the transport discards the
/// value at the `.discovered` handler.
struct DiscoveredDevice: Equatable, Sendable, Identifiable {
    /// `CBPeripheral.identifier` — stable per device per iOS install, and the key the
    /// merge dedupes on.
    let id: UUID
    /// Advertised name, or nil if the peripheral didn't advertise one.
    let name: String?
    /// What this peripheral advertises itself as. Exactly one element as a client
    /// emits it — a radar stream contains only radars — and the union of every client
    /// that saw it once merged, so a device speaking two supported profiles is one row
    /// carrying both tags.
    var kinds: Set<SensorKind>
    /// Roles the reporting client holds this peripheral under *right now*.
    ///
    /// Live tenancy, not the rider's durable choice. For `BLECSCClient` that is the
    /// slot's role set, so a paired sensor out of range reports none; for the
    /// single-slot clients it is `[.radar]` / `[.heartRate]` whenever the peripheral
    /// matches the gate. The durable record lives in `AppPreferences.pairedSensors`,
    /// and the Sensors screen builds its Paired section from there for exactly that
    /// reason — a device that is merely out of range must not drop into Available
    /// with a Pair button.
    let roles: Set<SensorRole>
    /// Connection lifecycle, or nil when the reporting client holds no connection
    /// identity for this peripheral.
    let connectionState: SensorConnectionState?
    /// Battery percentage, or nil when unknown — nothing connected, or a device that
    /// doesn't expose the Battery Service (BLE.md §14).
    let batteryPercent: Int?
    /// What the sensor reported via 0x2A5C. **CSC only** — nil for radar and heart
    /// rate, and nil for a CSC sensor until it has been connected and read at least
    /// once this session. Drives the role prompt: only a `requiresRoleSelection`
    /// sensor is worth asking about.
    let capabilities: CSCCapabilities?

    init(
        id: UUID,
        name: String?,
        kinds: Set<SensorKind>,
        roles: Set<SensorRole> = [],
        connectionState: SensorConnectionState? = nil,
        batteryPercent: Int? = nil,
        capabilities: CSCCapabilities? = nil
    ) {
        self.id = id
        self.name = name
        self.kinds = kinds
        self.roles = roles
        self.connectionState = connectionState
        self.batteryPercent = batteryPercent
        self.capabilities = capabilities
    }

    /// Holds at least one role in the client right now — see `roles` for why this is
    /// not the same question as "has the rider paired it".
    var isPaired: Bool { !roles.isEmpty }

    /// Connected, whatever it is doing with its roles.
    var isConnected: Bool { connectionState == .connected || connectionState == .active }
}

// MARK: - Merging

extension DiscoveredDevice {
    /// Fold a second client's view of the same peripheral into this one (#98).
    ///
    /// Only reachable when two clients both admitted the peripheral, which means it
    /// advertised two supported services — a combo the rider sees as one device. Each
    /// client answers only for its own profile, so the fold is a union where both can
    /// speak and a "first that knows" everywhere else.
    func merged(with other: DiscoveredDevice) -> DiscoveredDevice {
        precondition(id == other.id, "merging rows for different peripherals")
        return DiscoveredDevice(
            id: id,
            name: name ?? other.name,
            kinds: kinds.union(other.kinds),
            // Union, not replace: a device can genuinely hold a CSC role in one client
            // and the radar role in another, and dropping either would understate what
            // is currently connected.
            roles: roles.union(other.roles),
            // The liveliest wins. Two clients can hold the same peripheral at different
            // points of their own lifecycles, and a row saying "Disconnected" next to a
            // sensor that is streaming would be the wrong half of the truth.
            connectionState: [connectionState, other.connectionState]
                .compactMap { $0 }
                .max { Self.liveliness($0) < Self.liveliness($1) },
            // 0x180F is one service on one peripheral, so whichever client got the read
            // read the same value.
            batteryPercent: batteryPercent ?? other.batteryPercent,
            capabilities: capabilities ?? other.capabilities
        )
    }

    /// How far through the connection lifecycle a state is, for picking between two
    /// clients' answers. Ordering only — the numbers mean nothing else.
    private static func liveliness(_ state: SensorConnectionState) -> Int {
        switch state {
        case .disconnected:  0
        case .scanning:      1
        case .reconnecting:  2
        case .connecting:    3
        case .connected:     4
        case .active:        5
        }
    }
}
