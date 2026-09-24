import Charts
import ComposableArchitecture
import SwiftUI

/// S10 — Ride Summary, presented as a sheet by `AppFeature` when a ride is finished (#249).
///
/// The Design.sketch S10 frame's structure — map, a grouped list, a floating button — carrying
/// UX.md §S10's content. The frame's Description, Bike and Sync To rows are not built: Sync is
/// Phase 2, and there is no bike model. This view owns only the loading, which a snapshot must
/// not run; the screen itself is `RideSummaryList`.
struct RideSummaryView: View {
    let store: StoreOf<RideSummaryFeature>

    /// The frame's map placeholder height.
    static let mapHeight: CGFloat = 168
    static let chartHeight: CGFloat = 140
    static let pieHeight: CGFloat = 160

    var body: some View {
        NavigationStack {
            RideSummaryList(store: store)
        }
        .task { await store.send(.task).finish() }
    }
}

/// S10's content, rendered from state alone so a snapshot can seed it. Generic over the map row
/// for `RideDetailList`'s reason: a live `Map` can't be pixel-snapshotted reproducibly.
struct RideSummaryList<MapRow: View>: View {
    @Bindable var store: StoreOf<RideSummaryFeature>
    let mapRow: MapRow

    @FocusState private var isNameFocused: Bool

    var body: some View {
        let unit = store.unitSystem
        List {
            Section {
                mapRow
                    .frame(height: RideSummaryView.mapHeight)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerMd, style: .continuous))
                    .listRowInsets(EdgeInsets())
            }
            Section {
                // The whole row focuses the field, not only the text: the rider taps the title.
                LabeledContent("Name") {
                    TextField("Name", text: $store.title.sending(\.titleChanged))
                        .multilineTextAlignment(.trailing)
                        .submitLabel(.done)
                        .focused($isNameFocused)
                        .foregroundStyle(Color.cyTextSecondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { isNameFocused = true }
            }
            Section("Ride Stats") {
                switch store.load {
                case .waiting:
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                case .unavailable:
                    unavailable("This ride's stats couldn't be loaded")
                case .loaded:
                    stats(unit)
                }
            }
            if store.load == .loaded {
                Section("Elevation Profile") {
                    if let profile = store.elevationProfileMeters {
                        ElevationProfileView(samples: profile.map(unit.elevation(fromMeters:)),
                                             unitLabel: unit.elevationLabel)
                            .frame(height: RideSummaryView.chartHeight)
                            .padding(.vertical, Spacing.sm)
                    } else {
                        unavailable("No elevation recorded")
                    }
                }
                Section("Heart Rate Zones") {
                    let zoneSeconds = store.heartRateZoneSeconds
                    if zoneSeconds.isEmpty {
                        unavailable("No heart rate recorded")
                    } else {
                        HeartRateZonePie(zoneSeconds: zoneSeconds)
                            .padding(.vertical, Spacing.sm)
                    }
                }
            }
        }
        .navigationTitle("Finish Ride")
        .navigationBarTitleDisplayMode(.inline)
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

    @ViewBuilder
    private func stats(_ unit: UnitSystem) -> some View {
        if let summary = store.summary {
            LabeledContent("Distance",
                           value: "\(unit.distance(fromMeters: summary.distanceMeters).formatted(.number.precision(.fractionLength(1)))) \(unit.distanceLabel)")
            LabeledContent("Time", value: Duration.seconds(summary.durationSeconds)
                .formatted(.time(pattern: .hourMinuteSecond(padHourToLength: 1))))
        }
        LabeledContent("Avg Speed", value: speedText(store.stats?.averageSpeedMPS, unit))
        // Absent, not 0, with no cadence sensor — 0 rpm is a real reading.
        if let cadence = store.stats?.averageCadenceRPM {
            LabeledContent("Avg Cadence", value: "\(cadence.formatted()) rpm")
        }
        // Absent with no radar paired, where "0 passes" would be a claim nobody measured.
        if let passes = store.stats?.vehiclePassCount {
            LabeledContent("Vehicle Passes", value: passes.formatted())
        }
        if let route = store.stats?.routeName {
            LabeledContent("Route", value: route)
        }
    }

    private func unavailable(_ text: String) -> some View {
        Text(text).foregroundStyle(Color.cyTextSecondary)
    }

    private func speedText(_ mps: Double?, _ unit: UnitSystem) -> String {
        guard let mps else { return "—" }
        return "\(unit.speed(fromMPS: mps).formatted(.number.precision(.fractionLength(1)))) \(unit.speedLabel)"
    }
}

extension RideSummaryList where MapRow == RideMapView {
    init(store: StoreOf<RideSummaryFeature>) {
        self.init(store: store, mapRow: RideMapView(segments: store.trackSegments,
                                                    passes: [],
                                                    unitSystem: store.unitSystem))
    }
}

// MARK: - HR Zone Pie

/// UX.md §S10's zone breakdown: a pie in the zone colours, with each zone's time beside it.
/// Zones the ride never reached are left out of both.
struct HeartRateZonePie: View {
    /// Seconds in each zone, zone 1 first.
    let zoneSeconds: [Int]

    private var zones: [(zone: Int, seconds: Int)] {
        zoneSeconds.enumerated().map { (zone: $0.offset + 1, seconds: $0.element) }.filter { $0.seconds > 0 }
    }

    var body: some View {
        HStack(spacing: Spacing.lg) {
            Chart(zones, id: \.zone) { entry in
                SectorMark(angle: .value("Time", entry.seconds), angularInset: 1)
                    .foregroundStyle(Color.hrZone(entry.zone))
            }
            .chartLegend(.hidden)
            .frame(width: RideSummaryView.pieHeight, height: RideSummaryView.pieHeight)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(zones, id: \.zone) { entry in
                    HStack(spacing: Spacing.sm) {
                        Circle()
                            .fill(Color.hrZone(entry.zone))
                            .frame(width: Spacing.sm, height: Spacing.sm)
                        Text("Z\(entry.zone)")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: Spacing.xs)
                        Text(Duration.seconds(entry.seconds)
                            .formatted(.time(pattern: .hourMinuteSecond(padHourToLength: 1))))
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(Color.cyTextSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
