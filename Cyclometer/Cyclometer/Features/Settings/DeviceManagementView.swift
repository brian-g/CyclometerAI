import SwiftUI
import ComposableArchitecture

/// S11 — the Manage Sensors screen pushed from Settings.
///
/// Nothing but the title: everything that is the list lives in `DeviceListView`, so
/// S02 — Add Sensors (#107) can present the same list under its own title and helper
/// text without copying it.
struct DeviceManagementView: View {
    let store: StoreOf<DeviceManagementFeature>

    var body: some View {
        DeviceListView(store: store)
            .navigationTitle("Manage Sensors")
    }
}

/// The device list itself — one flat grouped list of everything discovered or paired,
/// mixing radar, heart rate and CSC (UX.md §S11, `Design.sketch` — S11).
///
/// Flat rather than sectioned by role: role is established at pairing time and shown in
/// the subtitle, and a role-keyed list would have had to invent somewhere to put an
/// unpaired device whose 0x2A5C read has not returned yet. Paired sensors sort to the
/// top, which `listedDevices` already does.
struct DeviceListView: View {
    @Bindable var store: StoreOf<DeviceManagementFeature>

    var body: some View {
        let paired = store.pairedRoles
        List {
            Section {
                ForEach(store.listedDevices) { device in
                    let roles = paired[device.id] ?? []
                    DeviceRow(device: device, pairedRoles: roles) {
                        store.send(
                            roles.isEmpty
                                ? .pairButtonTapped(device.id)
                                : .unpairButtonTapped(device.id)
                        )
                    }
                    // Tapping a combo sensor re-opens the role prompt —
                    // BLE.md §5.0's "reassignable without re-pairing". Rows
                    // with nothing to choose stay inert.
                    .contentShape(.rect)
                    .onTapGesture { store.send(.rowTapped(device.id)) }
                }

                // Always last, and always present: the scan runs for as long as this
                // screen is open, so there is no state in which it has finished. With
                // nothing found this row *is* the empty state, which is why the empty
                // case needs no separate branch — only the footer's extra hint.
                HStack(spacing: Spacing.sm) {
                    ProgressView().controlSize(.small)
                    Text("Searching for sensors…")
                        .font(.subheadline)
                        .foregroundStyle(Color.cyTextSecondary)
                }
            } header: {
                Text("Tap to pair, pull to refresh.")
                    // Body text below the title in the Sketch frame, not a section
                    // caption — so neither the uppercasing nor the caption size.
                    .textCase(nil)
                    .font(.body)
                    .foregroundStyle(Color.cyTextPrimary)
            } footer: {
                if store.listedDevices.isEmpty {
                    Text("Make sure your sensors are awake and within range.")
                }
            }
        }
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
    /// The rider's durable record for this peripheral, empty when it is merely
    /// discovered. Not `device.roles`, which is live tenancy in the reporting client
    /// and so is empty for a paired sensor that is out of range.
    let pairedRoles: Set<SensorRole>
    let onAction: () -> Void

    private var isPaired: Bool { !pairedRoles.isEmpty }

    var body: some View {
        SensorListRowView(
            icon: SensorKind.symbolName(for: device.kinds),
            title: device.name ?? "Unknown Sensor",
            subtitle: subtitle
        ) {
            // Only for a device that is actually up: a reconnecting sensor's last
            // known level would sit next to a "Reconnecting…" subtitle and read as
            // current.
            if let battery = device.batteryPercent, device.isConnected {
                SensorBatteryLabel(percent: battery)
            }
            SensorRowButton(isPaired ? "Unpair" : "Pair",
                            tint: isPaired ? .cyDestructive : .cyPrimary,
                            action: onAction)
        }
    }

    /// Roles held, or the connection state while it is still settling — a paired
    /// sensor that hasn't delivered a measurement yet would otherwise look idle.
    private var subtitle: String? {
        guard isPaired else { return nil }
        switch device.connectionState {
        case .active, .connected, .none:
            // Declaration order (radar, HR, speed, then cadence), not alphabetical — it
            // matches how roles are named everywhere else in the app and the specs.
            return SensorRole.allCases
                .filter(pairedRoles.contains)
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

#Preview("Manage Sensors") {
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

#Preview("Manage Sensors — searching") {
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
