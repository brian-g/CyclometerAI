import SwiftUI
import MapKit
import Charts
import ComposableArchitecture

struct RidesView: View {
    let store: StoreOf<RidesFeature>
    let onStartRide: () -> Void
    /// What the row dates are relative to. Snapshots pin it; the app leaves it nil and each
    /// row follows the clock (#291).
    var now: Date?

    var body: some View {
        Group {
            if store.hasLoaded && store.rides.isEmpty {
                emptyRides
            } else {
                rideList
            }
        }
        .navigationTitle("Rides")
        .task { store.send(.task) }
    }

    private var rideList: some View {
        List {
            ForEach(store.rides) { ride in
                NavigationLink(state: RideRoutePath.State.ride(RideDetailFeature.State(summary: ride))) {
                    RideRow(ride: ride, thumbnail: store.thumbnails[ride.id],
                            unitSystem: store.unitSystem, now: now)
                }
                .onAppear { store.send(.rowAppeared(ride.id)) }
                // Trailing Delete only. §S14's leading Sync and Make Route wait on
                // service sync (Phase 2) and a route-from-ride model, neither built (#248).
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deleteRide(ride.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    // `role: .destructive` alone is not enough: the app-wide `.tint` wins
                    // over the role inside a swipe action, so Delete rendered in the brand
                    // green.
                    .tint(Color.cyDestructive)
                }
            }
        }
        .listStyle(.plain)
    }

    private var emptyRides: some View {
        ContentUnavailableView {
            Label("No Rides Yet", systemImage: "figure.outdoor.cycle")
        } description: {
            Text("Your completed rides will appear here. Tap the Start Ride button below to get started!")
        } actions: {
            Button {
                onStartRide()
            } label: {
                Label("Start Ride", systemImage: "play.fill")
            }
            .labelStyle(.titleAndIcon)
            .buttonStyle(.borderedProminent)
            .tint(.cyPrimary)
        }
    }

    /// Goes through the reducer, which used to call `modelContext.delete(ride)` straight
    /// from here — that removed the one SwiftData row and left the ride's GPX file, its
    /// CoreData track points and its vehicle-pass events behind — nothing else knew the
    /// ride was gone (#261).
    private func deleteRide(_ id: UUID) {
        store.send(.deleteRecordedRide(id))
    }
}

// MARK: - Navigation stack

/// The Rides tab's navigation stack: S14 at the root, S15 pushed as `RideRoutePath` state
/// (#251), and S20 from S15's Route row (#426). One definition for the app, the previews and the
/// snapshot tests, for the reason `RoutesNavigationStack` gives: a `NavigationLink(state:)` row
/// outside a store-powered stack reports an issue and cannot push.
struct RidesNavigationStack: View {
    @Bindable var store: StoreOf<RidesFeature>
    /// Hides Start Ride while a ride records, as every tab does.
    var isStartRideHidden: Bool = false
    var onStartRide: () -> Void = {}
    /// See `RidesView.now`.
    var now: Date?

    var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            RidesView(store: store, onStartRide: onStartRide, now: now)
                .startRideToolbarItem(isHidden: isStartRideHidden, action: onStartRide)
        } destination: { pathStore in
            RideRoutePathView(store: pathStore, isUseRouteHidden: isStartRideHidden)
        }
    }
}

// MARK: - Ride Row

/// One ride in S14, laid out as `Design.sketch`'s S14 frame: thumbnail, name over date, then
/// time and distance side by side, each a small `HeroNumber` with its label beneath (#248).
/// Everything is formatted here from the stored values, so a units change in S12 shows on
/// the next render without a reload.
struct RideRow: View {
    let ride: RideListSummary
    let thumbnail: RidesFeature.Thumbnail?
    let unitSystem: UnitSystem
    /// See `RidesView.now`.
    let now: Date?

    /// Hours and minutes, no seconds ("0:45", "1:18") — a list reads at a glance, and the
    /// narrower value leaves the name room. Truncated like a ride clock, not rounded, so a
    /// 1:18:32 ride doesn't read as 1:19.
    private var elapsed: String {
        Duration.seconds(ride.durationSeconds)
            .formatted(.time(pattern: .hourMinute(padHourToLength: 1, roundSeconds: .down)))
    }

    private func dateText(now: Date) -> some View {
        Text(RideDateText.text(for: ride.startedAt, now: now))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            RideThumbnail(thumbnail: thumbnail)
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // S10 names every ride it shows (#249), but one recorded before it, or closed
                // out at launch, has a "" `title` — a blank row would read as broken.
                Text(ride.title.isEmpty ? "Ride" : ride.title)
                    .font(.headline)
                    .lineLimit(1)
                if let now {
                    dateText(now: now)
                } else {
                    // A `now` taken when the view was built would keep a list left open past
                    // midnight on the day before (#291). The timeline re-reads the clock each
                    // minute while the row is on screen, and again when it comes back.
                    TimelineView(.everyMinute) { context in
                        dateText(now: context.date)
                    }
                }
            }
            Spacer(minLength: Spacing.sm)
            // Fixed-size so the name and date truncate first — a clipped "1:1…" is no reading
            // at all. A minimum column width keeps values right-aligned down the list for the
            // common widths; a longer one (100 mi and up) widens only its own row.
            HStack(alignment: .top, spacing: Spacing.xs) {
                HeroNumber(elapsed, unit: "time")
                    .heroNumberSize(.small)
                    .layout(.vertical)
                    .frame(minWidth: Spacing.rideMetric, alignment: .trailing)
                HeroNumber(unitSystem.distance(fromMeters: ride.distanceMeters),
                           unit: unitSystem.distanceLabel)
                    .heroNumberSize(.small)
                    .layout(.vertical)
                    .frame(minWidth: Spacing.rideMetric, alignment: .trailing)
            }
            .fixedSize()
        }
    }
}

/// The ride's stored map image (#177) in the current appearance, or a placeholder while it
/// loads and for a ride with none — recorded before #177, with no GPS track, or whose capture
/// hasn't landed yet. Same frame either way, so a missing image never collapses the row.
struct RideThumbnail: View {
    let thumbnail: RidesFeature.Thumbnail?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if case .loaded(let images) = thumbnail {
                Image(uiImage: colorScheme == .dark ? images.dark : images.light)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.cyBgTertiary
                    .overlay {
                        Image(systemName: "map")
                            .font(.title3)
                            .foregroundStyle(Color.cyTextTertiary)
                    }
                    .accessibilityHidden(true)
            }
        }
        .frame(width: Spacing.rideThumbnail, height: Spacing.rideThumbnail)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerSm, style: .continuous))
    }
}

// MARK: - Chart Views

struct ElevationProfileView: View {
    let samples: [Double]
    /// The unit `samples` are already in. This view plots and labels; it does not convert. S20
    /// follows the S12 units picker (#195), while ride history's demo data is in feet.
    let unitLabel: String
    private var points: [ElevationPoint] { ElevationPoint.points(from: samples) }
    var body: some View {
        Chart(points) { point in
            AreaMark(x: .value("Distance", point.distance), y: .value("Elevation", point.elevation))
                .foregroundStyle(Color.cyPrimary.opacity(0.18)).interpolationMethod(.catmullRom)
            LineMark(x: .value("Distance", point.distance), y: .value("Elevation", point.elevation))
                .foregroundStyle(Color.cyPrimary)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: [samples.min() ?? 0, samples.max() ?? 1]) { value in
                AxisValueLabel { if let e = value.as(Double.self) { Text("\(Int(e)) \(unitLabel)").monospacedDigit() } }
            }
        }
    }
}

// MARK: - Supporting Types

// Identified by sample index, so the same samples give Charts the same identities on every
// rebuild — a fresh `UUID()` per point defeated its diffing (#348).
struct ElevationPoint: Identifiable, Equatable {
    let distance: Int; let elevation: Double
    var id: Int { distance }

    static func points(from samples: [Double]) -> [ElevationPoint] {
        samples.enumerated().map { ElevationPoint(distance: $0.offset, elevation: $0.element) }
    }
}

#Preview("Rides") {
    let rides = [
        RideListSummary(id: UUID(), title: "River Loop", startedAt: .now.addingTimeInterval(-86_400),
                        distanceMeters: 36_050, durationSeconds: 4_712),
        RideListSummary(id: UUID(), title: "Summit Climb", startedAt: .now.addingTimeInterval(-3 * 86_400),
                        distanceMeters: 51_200, durationSeconds: 7_865)
    ]
    // Seeded through the client, not `RidesFeature.State(rides:)` directly: the view's
    // own `.task` fires regardless and would otherwise reload through an unmocked
    // `persistenceClient`, clobbering seeded state with an empty list almost immediately.
    return withDependencies {
        $0.persistenceClient = .mock(rides: rides)
    } operation: {
        RidesNavigationStack(
            store: Store(initialState: RidesFeature.State()) { RidesFeature() },
            onStartRide: {}
        )
    }
}

#Preview("Rides — empty") {
    withDependencies {
        $0.persistenceClient = .mock()
    } operation: {
        RidesNavigationStack(
            store: Store(initialState: RidesFeature.State()) { RidesFeature() },
            onStartRide: {}
        )
    }
}
