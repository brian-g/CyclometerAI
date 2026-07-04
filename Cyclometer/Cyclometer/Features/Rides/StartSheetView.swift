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
                    ForEach(store.sensors) { sensor in
                        SensorStatusRow(sensor: sensor)
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

private struct SensorStatusRow: View {
    let sensor: SensorRow

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: sensor.kind.systemImage)
                .font(.headline)
                .foregroundStyle(sensor.kind.tint)
                .frame(width: Spacing.xxl, height: Spacing.xxl)
                .background(sensor.kind.tint.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: Spacing.cornerMd))

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(sensor.kind.displayName).font(.headline)
                Text(sensor.name ?? "Not Paired")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let battery = sensor.batteryPercent, sensor.status == .connected {
                Label("\(battery)%", systemImage: "battery.100")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            statusBadge
        }
        .padding(.vertical, Spacing.xs)
    }

    private var statusBadge: some View {
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

#Preview("Start Sheet") {
    StartSheetView(
        store: Store(
            initialState: StartSheetFeature.State(
                sensors: [
                    SensorRow(kind: .radar, name: "Varia RTL515", status: .connected, batteryPercent: 82),
                    SensorRow(kind: .heartRate, name: "HRM-Dual", status: .connected),
                    SensorRow(kind: .speed, status: .searching),
                    SensorRow(kind: .cadence, status: .notPaired)
                ]
            )
        ) {
            StartSheetFeature()
        }
    )
}
