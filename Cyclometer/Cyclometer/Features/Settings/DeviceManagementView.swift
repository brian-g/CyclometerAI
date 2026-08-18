import SwiftUI
import ComposableArchitecture

/// S11 — the Sensors screen pushed from Settings. Lists radar, heart rate and CSC
/// devices in one merged list (#98); #100 replaces the two sections below with the flat
/// Sketch layout and adds pairing for the first two kinds.
struct DeviceManagementView: View {
    @Bindable var store: StoreOf<DeviceManagementFeature>

    var body: some View {
        List {
            if !store.pairedDevices.isEmpty {
                Section {
                    ForEach(store.pairedDevices) { device in
                        DeviceRow(device: device) { store.send(.unpairButtonTapped(device.id)) }
                            // Tapping a combo sensor re-opens the role prompt —
                            // BLE.md §5.0's "reassignable without re-pairing". Rows
                            // with nothing to choose stay inert.
                            .contentShape(.rect)
                            .onTapGesture { store.send(.rowTapped(device.id)) }
                    }
                } header: {
                    Text("Paired")
                } footer: {
                    if !store.reassignableIDs.isEmpty {
                        Text("Tap a sensor that measures both to change what it does.")
                    }
                }
            }

            Section {
                if store.availableDevices.isEmpty {
                    // No empty state for the Paired section: it is hidden entirely
                    // when nothing is paired, so this is the only "nothing yet" case.
                    // The section header already says "Available", so the spinner
                    // alone carries the message.
                    ProgressView().controlSize(.small)
                } else {
                    ForEach(store.availableDevices) { device in
                        DeviceRow(device: device) { store.send(.pairButtonTapped(device.id)) }
                    }
                }
            } header: {
                Text("Available")
            } footer: {
                Text("Radar and heart rate sensors are listed here; pairing them arrives with full device management.")
            }
        }
        .navigationTitle("Sensors")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog($store.scope(state: \.roleDialog, action: \.roleDialog))
        // A separate modifier from the role sheet on purpose: the two are raised back
        // to back on a collision, and one `.confirmationDialog` cannot present the
        // second while the first is still dismissing.
        .alert($store.scope(state: \.collisionAlert, action: \.collisionAlert))
        .refreshable { await store.send(.refreshRequested).finish() }
        .task { await store.send(.task).finish() }
        .onDisappear { store.send(.onDisappear) }
    }
}

/// One discovered peripheral. The row skeleton is `SensorListRowView`, shared with
/// the Start sheet's Sensors group; what differs is what fills it — this models a
/// *device* that appears and disappears as scanning proceeds and carries a
/// pair/unpair action, rather than a fixed sensor category.
private struct DeviceRow: View {
    let device: DiscoveredDevice
    let onAction: () -> Void

    var body: some View {
        SensorListRowView(
            icon: "sensor.tag.radiowaves.forward",
            title: device.name ?? "Unknown Sensor",
            subtitle: subtitle
        ) {
            // Only for a device that is actually up: a reconnecting sensor's last
            // known level would sit next to a "Reconnecting…" subtitle and read as
            // current.
            if let battery = device.batteryPercent, device.isConnected {
                SensorBatteryLabel(percent: battery)
            }
            // Pairing is CSC-only until #100 writes `.radar` and `.heartRate` records,
            // so a radar or a strap lists and reports its status but offers no action —
            // a button that cannot do anything would be worse than none.
            if isActionable {
                SensorRowButton(holdsCSCRole ? "Unpair" : "Pair",
                                tint: holdsCSCRole ? .cyDestructive : .cyPrimary,
                                action: onAction)
            }
        }
    }

    /// Whether this row's button can do anything. True for a device advertising CSC,
    /// and for one already holding a CSC role — which covers the out-of-range paired
    /// sensor, whose row is synthesised from the record and so carries no advertised
    /// kinds beyond what the record implies.
    private var isActionable: Bool {
        device.kinds.contains(.speedCadence) || holdsCSCRole
    }

    /// Keyed on CSC tenancy rather than `isPaired`, because this button only ever acts
    /// on CSC records (#93). A combo already paired for heart rate sorts into Paired —
    /// it *is* paired — but its speed and cadence roles are still free, so it keeps a
    /// Pair button rather than an Unpair one that would silently do nothing.
    private var holdsCSCRole: Bool {
        !device.roles.isDisjoint(with: SensorRole.cscRoles)
    }

    /// Roles held, or the connection state while it is still settling — a paired
    /// sensor that hasn't delivered a measurement yet would otherwise look idle.
    private var subtitle: String? {
        guard device.isPaired else { return nil }
        switch device.connectionState {
        case .active, .connected, .none:
            // Declaration order (radar, HR, speed, then cadence), not alphabetical — it
            // matches how roles are named everywhere else in the app and the specs.
            return SensorRole.allCases
                .filter(device.roles.contains)
                .map(\.displayName)
                .joined(separator: " · ")
        case .connecting:    return "Connecting…"
        case .reconnecting:  return "Reconnecting…"
        case .scanning:      return "Searching…"
        case .disconnected:  return "Disconnected"
        }
    }
}

// MARK: - Previews

// All three clients must be overridden. Previews resolve dependencies to `liveValue`
// — there is no `previewValue` on any of them — so without an override the screen
// spins up a real CBCentralManager, and each live stream's empty replay clears its
// slice of the list on appear. Seeding `State.sources` alone cannot survive that.
//
// The populated preview does both: the stub streams are what actually feed the screen
// once `.task` runs, and the seeded state means the rows are still there in any host
// that renders without running `.task` (an image snapshot, for one).

private func stubbedDevices<Client>(
    _ client: inout Client,
    _ keyPath: WritableKeyPath<Client, @Sendable () -> AsyncStream<[DiscoveredDevice]>>,
    _ devices: [DiscoveredDevice]
) {
    client[keyPath: keyPath] = {
        AsyncStream { continuation in
            continuation.yield(devices)
            continuation.finish()
        }
    }
}

#Preview("Sensors") {
    NavigationStack {
        DeviceManagementView(
            store: Store(
                initialState: DeviceManagementFeature.State(sources: [
                    .speedCadence: DeviceDemoData.cscSensors,
                    .radar: DeviceDemoData.radarDevices,
                    .heartRate: DeviceDemoData.hrDevices
                ])
            ) {
                DeviceManagementFeature()
            } withDependencies: {
                var csc = BLECSCClient.testValue
                stubbedDevices(&csc, \.discoveredDevices, DeviceDemoData.cscSensors)
                $0.bleCSCClient = csc

                var radar = VariaRadarClient.testValue
                stubbedDevices(&radar, \.discoveredDevices, DeviceDemoData.radarDevices)
                $0.variaRadarClient = radar

                var hr = BLEHRClient.testValue
                stubbedDevices(&hr, \.discoveredDevices, DeviceDemoData.hrDevices)
                $0.bleHRClient = hr
            }
        )
    }
}

#Preview("Sensors — searching") {
    NavigationStack {
        DeviceManagementView(
            store: Store(initialState: DeviceManagementFeature.State()) {
                DeviceManagementFeature()
            } withDependencies: {
                // Every testValue stream finishes without yielding — the empty case.
                $0.bleCSCClient = .testValue
                $0.variaRadarClient = .testValue
                $0.bleHRClient = .testValue
            }
        )
    }
}
