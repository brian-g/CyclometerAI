import SwiftUI
import ComposableArchitecture

/// S11 (subset) — the Sensors screen pushed from Settings.
struct DeviceManagementView: View {
    let store: StoreOf<DeviceManagementFeature>

    var body: some View {
        List {
            if !store.pairedDevices.isEmpty {
                Section("Paired") {
                    ForEach(store.pairedDevices) { device in
                        DeviceRow(device: device) { store.send(.unpairButtonTapped(device.id)) }
                    }
                }
            }

            Section {
                if store.availableDevices.isEmpty {
                    // No empty state for the Paired section: it is hidden entirely
                    // when nothing is paired, so this is the only "nothing yet" case.
                    HStack(spacing: Spacing.sm) {
                        ProgressView().controlSize(.small)
                        Text("Searching for sensors").foregroundStyle(.secondary)
                    }
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
        .task { await store.send(.task).finish() }
        .onDisappear { store.send(.onDisappear) }
    }
}

/// One discovered peripheral. Purpose-built rather than reusing `SensorStatusRow`
/// from the Start sheet: that row models a fixed *category* (Radar / HR / Speed /
/// Cadence) with a status badge, whereas this models a *device* that appears and
/// disappears as scanning proceeds and carries a pair/unpair action.
private struct DeviceRow: View {
    let device: BLECSCClient.DiscoveredSensor
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "sensor.tag.radiowaves.forward")
                .font(.headline)
                .foregroundStyle(.cyPrimary)
                .frame(width: Spacing.xxl, height: Spacing.xxl)
                .background(Color.cyPrimary.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: Spacing.cornerMd))

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(device.name ?? "Unknown Sensor").font(.headline)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            actionButton
        }
        .padding(.vertical, Spacing.xs)
    }

    /// Roles held, or the connection state while it is still settling — a paired
    /// sensor that hasn't delivered a measurement yet would otherwise look idle.
    private var subtitle: String? {
        guard device.isPaired else { return nil }
        switch device.connectionState {
        case .active, .connected, .none:
            // Declaration order (speed, then cadence), not alphabetical — it matches
            // how the pair is named everywhere else in the app and the specs.
            return BLECSCClient.SensorRole.allCases
                .filter(device.roles.contains)
                .map(\.displayName)
                .joined(separator: " · ")
        case .connecting:    return "Connecting…"
        case .reconnecting:  return "Reconnecting…"
        case .scanning:      return "Searching…"
        case .disconnected:  return "Disconnected"
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        Button(device.isPaired ? "Unpair" : "Pair", action: onAction)
            .font(.caption.weight(.semibold))
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(device.isPaired ? .cyDestructive : .cyPrimary)
    }
}

extension BLECSCClient.SensorRole {
    var displayName: String {
        switch self {
        case .speed:   "Speed"
        case .cadence: "Cadence"
        }
    }
}

// MARK: - Previews

#Preview("Sensors") {
    NavigationStack {
        DeviceManagementView(
            store: Store(
                initialState: DeviceManagementFeature.State(
                    devices: [
                        .init(id: UUID(), name: "Wahoo RPM", roles: [.speed, .cadence], connectionState: .active),
                        .init(id: UUID(), name: "GSC-10", roles: [], connectionState: nil),
                        .init(id: UUID(), name: nil, roles: [], connectionState: nil)
                    ]
                )
            ) { DeviceManagementFeature() }
        )
    }
}

#Preview("Sensors — searching") {
    NavigationStack {
        DeviceManagementView(
            store: Store(initialState: DeviceManagementFeature.State()) { DeviceManagementFeature() }
        )
    }
}
