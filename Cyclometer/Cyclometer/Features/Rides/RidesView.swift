import SwiftUI
import MapKit
import Charts
import ComposableArchitecture

struct RidesView: View {
    let store: StoreOf<RidesFeature>
    let onStartRide: () -> Void

    private var rideSummaries: [RideSummary] {
        store.rides.map(RideSummary.recorded)
    }

    var body: some View {
        List {
            if store.hasLoaded && rideSummaries.isEmpty {
                ContentUnavailableView {
                    Label("No Rides Yet", systemImage: "figure.outdoor.cycle")
                } description: {
                    Text("Start a ride to see it appear here.")
                } actions: {
                    Button("Start New Ride", action: onStartRide)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
                .listRowBackground(Color.clear)
            } else {
                ForEach(rideSummaries) { ride in
                    NavigationLink {
                        RideDetailView(ride: ride.detail)
                    } label: {
                        RideRow(ride: ride)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button { } label: {
                            Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .tint(.blue)
                        Button { } label: {
                            Label("Make Route", systemImage: RouteLibrary.symbolName)
                        }
                        .tint(.green)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteRide(ride)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        // `role: .destructive` alone is not enough: the app-wide `.tint` wins
                        // over the role inside a swipe action, so Delete rendered in the brand
                        // green — the same colour as "Make Route" beside it.
                        .tint(Color.cyDestructive)
                    }
                }
            }
        }
        .navigationTitle("Rides")
        .task { store.send(.task) }
    }

    /// Goes through the reducer, which used to call `modelContext.delete(ride)` straight
    /// from here — that removed the one SwiftData row and left the ride's GPX file, its
    /// CoreData track points and its vehicle-pass events behind — nothing else knew the
    /// ride was gone (#261).
    private func deleteRide(_ ride: RideSummary) {
        store.send(.deleteRecordedRide(ride.id))
    }
}

// MARK: - Ride Row

struct RideRow: View {
    let ride: RideSummary
    var body: some View {
        HStack(spacing: 8) {
            RideMapThumbnailView(ride: ride.detail)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(ride.title).font(.headline)
                Text(ride.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 10)
            VStack(alignment: .trailing, spacing: 4) {
                HeroNumber(ride.distance, unit: "mi").heroNumberSize(.small).layout(.horizontal)
                Text(ride.elapsedTime).dDINCondensed(size: 20, relativeTo: .footnote)
            }
        }
    }
}

// MARK: - Ride Detail View

struct RideDetailView: View {
    let ride: RideDetail
    var body: some View {
        List {
            Section {
                RideMapView(ride: ride)
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
            Section("Elevation Profile") {
                ElevationProfileView(samples: ride.elevationSamples, unitLabel: "ft")
                    .frame(height: 140).padding(.vertical, 8)
            }
            Section("Stats") {
                LabeledContent("Avg Speed (mph)", value: ride.averageSpeed)
                LabeledContent("Max Speed (mph)", value: ride.maxSpeed)
                LabeledContent("Avg Cadence (rpm)", value: ride.averageCadence)
                LabeledContent("Max Cadence (rpm)", value: ride.maxCadence)
            }
            Section("HR Profile") {
                HeartRateProfileView(samples: ride.heartRateSamples)
                    .frame(height: 140).padding(.vertical, 8)
            }
            Section("Strava Segments") {
                ForEach(ride.stravaSegments) { segment in
                    LabeledContent {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(segment.bestTime).font(.headline)
                            Text(segment.bestTimeDate, format: .dateTime.month(.abbreviated).day())
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(segment.name).font(.headline)
                            HStack(spacing: 2) { Text(segment.distance); Text("mi") }
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(ride.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Map Views

struct RideMapThumbnailView: View {
    let ride: RideDetail
    var body: some View {
        RideMapView(ride: ride, showsMarkers: false, showsControls: false)
            .allowsHitTesting(false)
    }
}

struct RideMapView: View {
    let ride: RideDetail
    var showsMarkers = true
    var showsControls = true
    var body: some View {
        Map(initialPosition: .region(ride.mapRegion)) {
            MapPolyline(coordinates: ride.coordinates)
                .stroke(Color.cyPrimary, lineWidth: showsMarkers ? 5 : 3)
            if showsMarkers {
                Marker("Start", systemImage: "flag.fill", coordinate: ride.startCoordinate)
                    .tint(Color.cyPrimary)
                Marker("Finish", systemImage: "flag.checkered", coordinate: ride.finishCoordinate)
                    .tint(.blue)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            if showsControls {
                MapCompass(); MapScaleView(); MapPitchToggle()
            }
        }
    }
}

// MARK: - Chart Views

struct HeartRateProfileView: View {
    let samples: [Int]
    private var points: [RideChartPoint] {
        samples.enumerated().map { RideChartPoint(distance: $0.offset, value: Double($0.element)) }
    }
    var body: some View {
        Chart(points) { point in
            AreaMark(x: .value("Distance", point.distance), y: .value("Heart Rate", point.value))
                .foregroundStyle(.red.opacity(0.14)).interpolationMethod(.catmullRom)
            LineMark(x: .value("Distance", point.distance), y: .value("Heart Rate", point.value))
                .foregroundStyle(.red)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: [samples.min() ?? 0, samples.max() ?? 1]) { value in
                AxisValueLabel { if let hr = value.as(Int.self) { Text("\(hr) bpm") } }
            }
        }
    }
}

struct ElevationProfileView: View {
    let samples: [Double]
    /// The unit `samples` are already in. This view plots and labels; it does not convert. S20
    /// follows the S12 units picker (#195), while ride history's demo data is in feet.
    let unitLabel: String
    private var points: [ElevationPoint] {
        samples.enumerated().map { ElevationPoint(distance: $0.offset, elevation: $0.element) }
    }
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

struct RideChartPoint: Identifiable {
    let id = UUID(); let distance: Int; let value: Double
}
struct ElevationPoint: Identifiable {
    let id = UUID(); let distance: Int; let elevation: Double
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
        NavigationStack {
            RidesView(
                store: Store(initialState: RidesFeature.State()) { RidesFeature() },
                onStartRide: {}
            )
        }
    }
}

#Preview("Rides — empty") {
    withDependencies {
        $0.persistenceClient = .mock()
    } operation: {
        NavigationStack {
            RidesView(
                store: Store(initialState: RidesFeature.State()) { RidesFeature() },
                onStartRide: {}
            )
        }
    }
}

struct RideSummary: Identifiable {
    let id: UUID; let title: String; let date: Date
    let elapsedTime: String; let distance: String
    let detail: RideDetail

    static func recorded(_ ride: RideListSummary) -> RideSummary {
        let detail = RideDetail.recordedRide(timestamp: ride.startedAt)
        return RideSummary(id: ride.id, title: detail.title, date: ride.startedAt,
                           elapsedTime: detail.elapsedTime, distance: detail.distance,
                           detail: detail)
    }
}
