import ComposableArchitecture
import SwiftUI

/// S05.1 — Start Ride sheet. TCA-wired setup screen presented from any tab.
struct StartSheetView: View {
    let store: StoreOf<StartSheetFeature>

    /// Found or paired sensors only; unpaired categories are never shown.
    private var visibleSensors: [SensorRow] {
        store.sensors.filter { $0.status != .notPaired }
    }

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
                    // Only surface sensors that are found or paired — never a fixed list of
                    // unpaired categories. With nothing found, show a single searching row.
                    if visibleSensors.isEmpty {
                        Text("Searching for sensors")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(visibleSensors) { sensor in
                            SensorStatusRow(sensor: sensor) {
                                store.send(.pairButtonTapped(sensor.kind))
                            }
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
    }
}

/// One sensor *category* in the Start sheet. Shares `SensorListRowView` with the
/// Sensors settings screen, which lists discovered *devices* instead.
private struct SensorStatusRow: View {
    let sensor: SensorRow
    /// Invoked when a found-but-unpaired sensor's "Tap to Pair" button is tapped.
    let onPair: () -> Void

    var body: some View {
        SensorListRowView(
            icon: sensor.kind.systemImage,
            iconTint: sensor.kind.tint,
            title: sensor.kind.displayName,
            // Device name only; the status control conveys connection state, so we
            // avoid a subtitle that could contradict it.
            subtitle: sensor.name
        ) {
            if let battery = sensor.batteryPercent, sensor.status == .connected {
                SensorBatteryLabel(percent: battery)
            }
            statusControl
        }
    }

    // Found sensors offer a pairing action; paired sensors show the connected badge.
    // `.notPaired` rows are filtered out upstream, so they render nothing here.
    @ViewBuilder
    private var statusControl: some View {
        switch sensor.status {
        case .searching:
            SensorRowButton("Tap to Pair", action: onPair)
        case .connected:
            let badge = sensor.status.badge
            Text(badge.label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .foregroundStyle(badge.foreground)
                .background(badge.background, in: Capsule())
        case .notPaired:
            EmptyView()
        }
    }
}

// MARK: - Previews

#Preview("Start Sheet") {
    StartSheetView(
        store: Store(
            initialState: StartSheetFeature.State(
                sensors: [
                    SensorRow(kind: .radar, name: "Varia RTL515", status: .connected, batteryPercent: 82),
                    SensorRow(kind: .heartRate, name: "HRM-Dual", status: .connected, batteryPercent: 14),
                    SensorRow(kind: .speed, status: .searching),
                    SensorRow(kind: .cadence, status: .notPaired)
                ]
            )
        ) {
            StartSheetFeature()
        }
    )
}
