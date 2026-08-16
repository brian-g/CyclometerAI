import SwiftUI
import ComposableArchitecture

/// S11 (subset) — the Sensors screen pushed from Settings.
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
                Text("Speed and cadence sensors only. Radar and heart rate pairing arrive with full device management.")
            }
        }
        .navigationTitle("Sensors")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog($store.scope(state: \.roleDialog, action: \.roleDialog))
        .task { await store.send(.task).finish() }
        .onDisappear { store.send(.onDisappear) }
    }
}

/// One discovered peripheral. The row skeleton is `SensorListRowView`, shared with
/// the Start sheet's Sensors group; what differs is what fills it — this models a
/// *device* that appears and disappears as scanning proceeds and carries a
/// pair/unpair action, rather than a fixed sensor category.
private struct DeviceRow: View {
    let device: BLECSCClient.DiscoveredSensor
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
            if let battery = device.batteryPercent, isUp {
                SensorBatteryLabel(percent: battery)
            }
            SensorRowButton(device.isPaired ? "Unpair" : "Pair",
                            tint: device.isPaired ? .cyDestructive : .cyPrimary,
                            action: onAction)
        }
    }

    /// Connected, whatever it is doing with its roles.
    private var isUp: Bool {
        device.connectionState == .connected || device.connectionState == .active
    }

    /// Roles held, or the connection state while it is still settling — a paired
    /// sensor that hasn't delivered a measurement yet would otherwise look idle.
    private var subtitle: String? {
        guard device.isPaired else { return nil }
        switch device.connectionState {
        case .active, .connected, .none:
            // Declaration order (speed, then cadence), not alphabetical — it matches
            // how the pair is named everywhere else in the app and the specs.
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

// Both previews must override `bleCSCClient`. Previews resolve dependencies to
// `liveValue` — there is no `previewValue` on this client — so without an override
// the screen spins up a real CBCentralManager, and the live stream's empty replay
// clears the list on appear. Seeding `State.devices` alone cannot survive that.
//
// The populated preview does both: the stub stream is what actually feeds the screen
// once `.task` runs, and the seeded state means the rows are still there in any host
// that renders without running `.task` (an image snapshot, for one).

#Preview("Sensors") {
    NavigationStack {
        DeviceManagementView(
            store: Store(
                initialState: DeviceManagementFeature.State(devices: DeviceDemoData.sensors)
            ) {
                DeviceManagementFeature()
            } withDependencies: {
                var client = BLECSCClient.testValue
                client.discoveredSensors = {
                    AsyncStream { continuation in
                        continuation.yield(DeviceDemoData.sensors)
                        continuation.finish()
                    }
                }
                $0.bleCSCClient = client
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
                // testValue's stream finishes without yielding — the empty case.
                $0.bleCSCClient = .testValue
            }
        )
    }
}
