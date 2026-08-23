import ComposableArchitecture
import SwiftUI

/// S02 — Add Sensors (#107). Title, helper text and a Next button wrap S11's
/// `DeviceListView` unmodified (UX.md §S02) — an onboarding rider sees the same list,
/// role prompts and replace-or-cancel behavior as Settings' Manage Sensors, just with
/// copy that talks to someone seeing it for the first time.
struct SensorPairingView: View {
    @Bindable var store: StoreOf<SensorPairingFeature>

    var body: some View {
        VStack(spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Add Sensors")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color.cyTextPrimary)
                Text("Nearby sensors, tap to pair, pull to refresh.")
                    .font(.subheadline)
                    .foregroundStyle(Color.cyTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Spacing.lg)
            .padding(.horizontal, Spacing.lg)

            // Onboarding's background is `cyBgPrimary` (white), not the system's
            // grouped-list gray `DeviceListView` paints by default in Settings' own
            // NavigationStack — hidden here so the list sits on the same background as
            // the title and Next button around it.
            DeviceListView(store: store.scope(state: \.deviceManagement, action: \.deviceManagement))
                .scrollContentBackground(.hidden)

            Button {
                store.send(.nextButtonTapped)
            } label: {
                Text("Next")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyPrimary)
            .padding([.horizontal, .bottom], Spacing.lg)
        }
    }
}

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

#Preview("Add Sensors — found") {
    SensorPairingView(
        store: Store(
            initialState: SensorPairingFeature.State(
                deviceManagement: DeviceManagementFeature.State(sources: [
                    .speedCadence: DeviceDemoData.cscSensors,
                    .radar: DeviceDemoData.radarDevices,
                    .heartRate: DeviceDemoData.hrDevices
                ])
            )
        ) {
            SensorPairingFeature()
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

#Preview("Add Sensors — searching") {
    SensorPairingView(
        store: Store(initialState: SensorPairingFeature.State()) {
            SensorPairingFeature()
        } withDependencies: {
            $0.bleCSCClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
        }
    )
}
