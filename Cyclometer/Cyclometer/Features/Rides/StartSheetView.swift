import ComposableArchitecture
import SwiftUI

/// S05.1 — Start Ride sheet. TCA-wired setup screen presented from any tab.
struct StartSheetView: View {
    let store: StoreOf<StartSheetFeature>

    var body: some View {
        NavigationStack {
            List {
                Section("Ride Setup") {
                    LabeledContent("Bike") { Text(NewRideDemoData.bikeName) }
                    // Route selection is Phase 2 (S05.2).
                    LabeledContent("Route") {
                        Text("Coming Soon").foregroundStyle(.secondary)
                    }
                }
                Section("Sensors") {
                    // Every paired sensor, connected or not — a rider setting up a ride
                    // needs to see that the strap they paired is the one about to be
                    // used, and whether it is up. Unpaired categories are absent, so
                    // with nothing paired the group says so rather than implying a scan
                    // that is not running.
                    if store.pairedRows.isEmpty {
                        HStack() {
                            Spacer()
                            Text("No paired sensors")
                                .foregroundStyle(Color.cyTextSecondary)
                            Spacer()
                        }
                    } else {
                        ForEach(store.pairedRows) { sensor in
                            SensorStatusRow(sensor: sensor)
                        }
                    }
                }
            }
            .navigationTitle("New Ride")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        store.send(.cancelButtonTapped)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.send(.startRideButtonTapped)
                    } label: {
                        Label("Start Ride", systemImage: "play.fill")
                    }.labelStyle(.titleAndIcon)
                    .buttonStyle(.borderedProminent)
                    .tint(.cyPrimary)
                }
            }
        }
        .task { await store.send(.task).finish() }
        .onDisappear { store.send(.onDisappear) }
    }
}

/// One sensor *category* in the Start sheet. Shares `SensorListRowView` with the
/// Sensors settings screen, which lists discovered *devices* instead.
///
/// No action: every row here is already paired, and pairing lives on S11. The row that
/// used to carry "Tap to Pair" was reachable only through a status the sheet can no
/// longer be in — offering it now would mean running discovery this screen does not do.
///
/// Internal rather than private so `StartSheetSnapshotTests` can pin it. The sheet as a
/// whole cannot be snapshotted: its toolbar renders blank inside a `UIHostingController`,
/// and a reference recorded from that is a test that can never fail.
struct SensorStatusRow: View {
    let sensor: SensorRow

    var body: some View {
        SensorListRowView(
            icon: sensor.kind.systemImage,
            iconTint: sensor.kind.tint,
            title: sensor.kind.displayName,
            // Device name only; the status control conveys connection state, so we
            // avoid a subtitle that could contradict it.
            subtitle: sensor.name
        ) {
            VStack(alignment: .trailing) {
                statusControl
                if let battery = sensor.batteryPercent, sensor.status == .connected {
                    SensorBatteryLabel(percent: battery)
                }
            }
        }
    }

    private var statusControl: some View {
        let badge = sensor.status.badge
        return Text(badge.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .foregroundStyle(badge.foreground)
            .background(badge.background, in: Capsule())
    }
}

// MARK: - Previews

// The rows come from the paired records, so the preview has to seed them — and in the
// same dependency scope the store reads, or the seed lands in different storage.
#Preview("Start Sheet") {
    withDependencies {
        $0.defaultFileStorage = .inMemory
    } operation: {
        @Shared(.appPreferences) var preferences
        $preferences.withLock {
            $0.pairedSensors = [
                PairedSensor(peripheralID: UUID(), role: .radar, displayName: "Varia RTL515"),
                PairedSensor(peripheralID: UUID(), role: .heartRate, displayName: "HRM-Dual with Long Name"),
                PairedSensor(peripheralID: UUID(), role: .speed, displayName: "Wahoo Cadence 8683")
            ]
        }
        return StartSheetView(
            store: Store(
                initialState: StartSheetFeature.State(
                    sensors: [
                        SensorRow(kind: .radar, status: .connected, batteryPercent: 82),
                        SensorRow(kind: .heartRate, status: .connected, batteryPercent: 14),
                        // Paired but out of range — the case the sheet exists to show.
                        SensorRow(kind: .speed, status: .searching),
                        SensorRow(kind: .cadence, status: .searching)
                    ]
                )
            ) {
                StartSheetFeature()
            } withDependencies: {
                $0.variaRadarClient = .testValue
                $0.bleHRClient = .testValue
                $0.bleCSCClient = .testValue
            }
        )
    }
}

#Preview("Start Sheet — nothing paired") {
    withDependencies {
        $0.defaultFileStorage = .inMemory
    } operation: {
        StartSheetView(
            store: Store(initialState: StartSheetFeature.State()) {
                StartSheetFeature()
            } withDependencies: {
                $0.variaRadarClient = .testValue
                $0.bleHRClient = .testValue
                $0.bleCSCClient = .testValue
            }
        )
    }
}
