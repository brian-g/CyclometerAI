import ComposableArchitecture
import SwiftUI

/// S05.1 — Start Ride sheet. TCA-wired setup screen presented from any tab.
///
/// Brings its own stack, driven by `StartSheetFeature.path`, so the Route row pushes S05.2 as
/// reducer state (#196).
struct StartSheetView: View {
    @Bindable var store: StoreOf<StartSheetFeature>

    var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            List {
                Section("Ride Setup") {
                    LabeledContent("Bike") { Text(NewRideDemoData.bikeName) }
                    // Seeded with the sheet's answer, so S05.2 opens with it checked.
                    NavigationLink(state: StartSheetFeature.Path.State.routePicker(
                        RoutePickerFeature.State(selection: store.route)
                    )) {
                        ActiveRouteRow(routeName: store.route?.name)
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
        } destination: { pathStore in
            switch pathStore.case {
            case .routePicker(let pickerStore):
                RoutePickerView(store: pickerStore)
            }
        }
        .task { await store.send(.task).finish() }
    }
}

/// The Ride Setup group's Route row: the route the ride will follow, or "None" (#196).
///
/// Internal rather than private so `StartSheetSnapshotTests` can pin it, as with `SensorStatusRow`.
/// The disclosure chevron is the `NavigationLink`'s, not this view's.
struct ActiveRouteRow: View {
    let routeName: String?

    var body: some View {
        LabeledContent("Route") {
            Text(routeName ?? "None")
                .lineLimit(1)
        }
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
//
// Each preview mocks the route library, so the Route row pushes a populated S05.2. There is no
// `PersistenceClient.previewValue`: without the mock a preview reads the live store.
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
                $0.persistenceClient = .mock(routes: RouteSummary.previewRoutes)
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
                $0.persistenceClient = .mock(routes: RouteSummary.previewRoutes)
            }
        )
    }
}

/// As S20's "Use This Route" opens it.
#Preview("Start Sheet — route chosen") {
    withDependencies {
        $0.defaultFileStorage = .inMemory
    } operation: {
        StartSheetView(
            store: Store(
                initialState: StartSheetFeature.State(route: RouteSummary.previewRoutes[1].reference)
            ) {
                StartSheetFeature()
            } withDependencies: {
                $0.variaRadarClient = .testValue
                $0.bleHRClient = .testValue
                $0.bleCSCClient = .testValue
                $0.persistenceClient = .mock(routes: RouteSummary.previewRoutes)
            }
        )
    }
}
