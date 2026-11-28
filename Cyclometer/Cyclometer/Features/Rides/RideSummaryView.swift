import ComposableArchitecture
import SwiftUI

/// S10 — Ride Summary, presented as a sheet by `AppFeature` when a ride is finished (#249).
///
/// The Design.sketch S10 frame's structure — map, a grouped list, a floating button — carrying
/// UX.md §S10's content: S15's Summary, led by distance and time (#645). The frame's Description
/// row is the Notes field (#645). Sync To is the "S10 - Ride Summary Sync Options" frame's row
/// of capsules (#631). Its Bike row is not built: there is no bike model. This view owns only the
/// loading, which a snapshot must not run; the screen itself is `RideSummaryList`.
struct RideSummaryView: View {
    @Bindable var store: StoreOf<RideSummaryFeature>

    /// The frame's map placeholder height.
    static let mapHeight: CGFloat = 168

    var body: some View {
        NavigationStack {
            RideSummaryList(store: store)
        }
        .alert($store.scope(state: \.alert, action: \.alert))
        .task { await store.send(.task).finish() }
    }
}

/// S10's content, rendered from state alone so a snapshot can seed it. Generic over the map row
/// for `RideDetailList`'s reason: a live `Map` can't be pixel-snapshotted reproducibly.
struct RideSummaryList<MapRow: View>: View {
    @Bindable var store: StoreOf<RideSummaryFeature>
    let mapRow: MapRow

    @FocusState private var isTitleFocused: Bool

    var body: some View {
        let unit = store.unitSystem
        List {
            Section {
                mapRow
                    .frame(height: RideSummaryView.mapHeight)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerMd, style: .continuous))
                    .listRowInsets(EdgeInsets())
            }
            // Labelled above their fields, as S15's Edit sheet lays them out (#645).
            Section("Title") {
                TextField("Title", text: $store.title.sending(\.titleChanged))
                    .submitLabel(.done)
                    .focused($isTitleFocused)
                    .onChange(of: isTitleFocused) { _, isFocused in
                        if isFocused { store.send(.titleFocused) }
                    }
            }
            Section("Notes") {
                TextField("Notes", text: $store.notes.sending(\.notesChanged), axis: .vertical)
                    .lineLimit(4...)
            }
            // On the page, not in a card, as the Sync Options frame draws it (#631).
            Section("Sync To") {
                SyncToCapsules(store: store)
                    .listRowBackground(Color.clear)
            }
            switch store.load {
            case .waiting:
                Section("Summary") {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            case .unavailable:
                Section("Summary") {
                    unavailable("This ride's stats couldn't be loaded")
                }
            case .loaded:
                // S15's Summary (#645), led by what S15 shows in its title block. A plain passes
                // row: S10 has no passes sheet.
                RideSummarySection(
                    stats: store.stats, unit: unit,
                    leading: store.summary?.leadingReadings(unit, movingSeconds: store.stats?.movingSeconds) ?? [],
                    // The stats read failed: say so, rather than a Summary that looks complete.
                    note: store.stats == nil ? "The rest of this ride's stats couldn't be loaded" : nil
                ) { passes in
                    LabeledContent("Vehicle Passes", value: passes.formatted())
                }
                // As S15 shows a route: here without a link, since S10 isn't on the Rides stack.
                if let route = store.stats?.routeName {
                    Section("Route") {
                        Text(route)
                    }
                }
                // Only when the ride flagged one (#391): a clean ride's summary is unchanged.
                let flagged = store.flaggedSensors
                if !flagged.isEmpty {
                    Section("Sensors") {
                        ForEach(flagged) { sensor in
                            // A device row, like S11's, so a combo sensor draws as it does there.
                            let style = SensorRowStyle.device(roles: Set(sensor.roles), kinds: [])
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                SensorListRowView(
                                    icon: style.symbol,
                                    iconTint: style.tint,
                                    title: sensor.roles.map(\.displayName).joined(separator: " & "),
                                    subtitle: sensor.name
                                ) { EmptyView() }
                                SensorWarningLabel(warning: sensor.warning)
                                    .padding(.bottom, Spacing.xs)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Finish Ride")
        .navigationBarTitleDisplayMode(.inline)
        // Not in the S10 frame (#452): the ride is already saved by now, so this is how a rider
        // throws it away. Leading, away from Finish Ride, and behind an alert.
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(role: .destructive) {
                    store.send(.deleteTapped)
                } label: {
                    Label("Delete Ride", systemImage: "trash")
                }
                // The app-wide tint beats the role otherwise, as in S14's swipe action.
                .tint(Color.cyDestructive)
                .disabled(store.load != .loaded)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button("Finish Ride") { store.send(.finishTapped) }
                .font(.headline)
                .padding(.horizontal, Spacing.sm)
                .buttonStyle(.glassProminent)
                .tint(.cyPrimary)
                .controlSize(.large)
                .padding(.bottom, Spacing.sm)
        }
    }

    private func unavailable(_ text: String) -> some View {
        Text(text).foregroundStyle(Color.cyTextSecondary)
    }
}

/// Sync To's capsules (#631), in one row, or one per line when the row won't fit (a large text
/// size, or several services).
private struct SyncToCapsules: View {
    let store: StoreOf<RideSummaryFeature>

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.sm) { capsules }
            VStack(alignment: .leading, spacing: Spacing.sm) { capsules }
        }
    }

    private var capsules: some View {
        ForEach(store.syncRows) { row in
            SyncToCapsule(destination: row.destination, isFilled: row.isChosen, needsReconnect: row.needsReconnect) {
                store.send(.syncDestinationTapped(row.destination))
            }
        }
    }
}

extension RideSummaryList where MapRow == RideMapView {
    init(store: StoreOf<RideSummaryFeature>) {
        self.init(store: store, mapRow: RideMapView(segments: store.trackSegments,
                                                    passes: [],
                                                    unitSystem: store.unitSystem))
    }
}

extension RideListSummary {
    /// S10's Summary leads with these (#645), ahead of S15's readings: S15 shows them in its
    /// title block instead. Time is moving time, W3's, as S15's title block and Avg Speed use;
    /// `movingSeconds` is nil when the stats didn't load, and then it falls back to the ride's
    /// time with pauses left out.
    func leadingReadings(_ unit: UnitSystem, movingSeconds: Int?) -> [SummaryReading] {
        let seconds = movingSeconds ?? Int(durationSeconds)
        return [
            SummaryReading(label: "Distance", reading: MetricReading(
                value: unit.distance(fromMeters: distanceMeters).formatted(.number.precision(.fractionLength(1))),
                unit: unit.distanceLabel, spoken: unit.spokenDistance(fromMeters: distanceMeters)
            )),
            SummaryReading(label: "Time", reading: MetricReading(value: seconds.formattedElapsed,
                                                                 spoken: seconds.spokenElapsed)),
        ]
    }
}

// MARK: - Previews

/// Every sensor: heart rate, cadence, radar and a Health body weight for calories, on a route.
private let previewStats = RideStats(
    averageSpeedMPS: 7.2, maxSpeedMPS: 12.4, averageCadenceRPM: 88, vehiclePassCount: 14,
    routeName: "River Loop", averageHeartRateBPM: 142, ascentMeters: 412, descentMeters: 398,
    activeKilocalories: 845, movingSeconds: 7_100
)

/// S10 as `.task` leaves it, seeded directly, with a placeholder map row.
@MainActor
private func previewList(
    load: RideSummaryFeature.State.Load = .loaded,
    stats: RideStats? = previewStats,
    notes: String = "",
    pairedSensors: [PairedSensor] = [],
    sensorHealth: [UUID: SensorHealthReport] = [:],
    connectedServices: [ConnectedService] = [],
    syncDestinationDefaults: [SyncDestination: Bool] = [:],
    rideId: UUID = UUID()
) -> some View {
    withDependencies {
        $0.defaultFileStorage = .inMemory
    } operation: {
        @Shared(.appPreferences) var preferences
        $preferences.withLock {
            $0.pairedSensors = pairedSensors
            $0.sensorHealth = sensorHealth
            $0.connectedServices = connectedServices
            $0.syncDestinationDefaults = syncDestinationDefaults
        }
        var state = RideSummaryFeature.State(rideId: rideId)
        state.load = load
        state.summary = RideListSummary(id: rideId, title: "", startedAt: .now,
                                        distanceMeters: 52_000, durationSeconds: 7_265)
        state.stats = stats
        state.title = "Morning Ride"
        state.notes = notes
        return NavigationStack {
            RideSummaryList(store: Store(initialState: state) { RideSummaryFeature() },
                            mapRow: Color.cyBgTertiary)
        }
    }
}

#Preview("Ride Summary") {
    previewList()
}

/// Notes typed in (#645): the field grows past its four lines.
#Preview("Ride Summary — notes") {
    previewList(notes: "Headwind the whole way out. Stopped at the bakery in Moorhead; the bridge on 12th is closed for paving, detour adds a mile.")
}

/// No HR strap, cadence sensor, radar or body weight, and a free ride: Distance, Time, Ascent,
/// Descent and Avg Speed alone, and no Route section.
#Preview("Ride Summary — GPS only") {
    previewList(stats: RideStats(averageSpeedMPS: 7.2, maxSpeedMPS: 12.4, ascentMeters: 412,
                                 descentMeters: 398, movingSeconds: 7_100))
}

/// The ride's stats read failed: Distance and Time come from the ride's row.
#Preview("Ride Summary — no stats") {
    previewList(stats: nil)
}

/// Waiting on the ride's finalize: the stats show progress and Delete is disabled (#452).
#Preview("Ride Summary — loading") {
    previewList(load: .waiting)
}

/// The ride flagged a sagging speed sensor and a flapping radar (#391).
#Preview("Ride Summary — unreliable sensors") {
    let rideId = UUID()
    let combo = UUID()
    let radar = UUID()
    return previewList(pairedSensors: [
        PairedSensor(peripheralID: combo, role: .speed, displayName: "Wahoo RPM"),
        PairedSensor(peripheralID: combo, role: .cadence, displayName: "Wahoo RPM"),
        PairedSensor(peripheralID: radar, role: .radar, displayName: "Varia RTL515")
    ], sensorHealth: [
        combo: SensorHealthReport(rideId: rideId, minBatteryPercent: 0, maxLinkLossesPerWindow: 43),
        radar: SensorHealthReport(rideId: rideId, minBatteryPercent: 70, maxLinkLossesPerWindow: 12)
    ], rideId: rideId)
}

private func previewStrava(isDisconnected: Bool = false) -> ConnectedService {
    ConnectedService(serviceType: .strava, keychainIdentifier: "strava", athleteID: "1",
                     grantedScopes: [StravaConfig.uploadScope], connectedAt: .now, isDisconnected: isDisconnected)
}

/// Strava connected, chosen as last time, and Apple Health left off last time (#631).
#Preview("Ride Summary — Sync To") {
    previewList(connectedServices: [previewStrava()],
                syncDestinationDefaults: [.appleHealth: false, .service(.strava): true])
}

/// Strava revoked access: its capsule offers Reconnect (#631).
#Preview("Ride Summary — Sync To reconnect") {
    previewList(connectedServices: [previewStrava(isDisconnected: true)])
}
