import SwiftUI
import SwiftData
import MapKit
import Charts
import ComposableArchitecture

struct RidesView: View {
    let store: StoreOf<RidesFeature>
    let recordedItems: [Ride]
    let onStartRide: () -> Void
    @Environment(\.modelContext) private var modelContext

    private var rideSummaries: [RideSummary] {
        store.demoRides.map(RideSummary.demo) + recordedItems.map(RideSummary.recorded)
    }

    var body: some View {
        List {
            if rideSummaries.isEmpty {
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
                            Label("Make Route", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                        }
                        .tint(.green)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteRide(ride)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Rides")
    }

    private func deleteRide(_ ride: RideSummary) {
        switch ride.source {
        case .demo(let id):
            store.send(.deleteDemoRide(id))
        case .recorded(let ride):
            modelContext.delete(ride)
        }
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
                ElevationProfileView(samples: ride.elevationSamples)
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
                AxisValueLabel { if let e = value.as(Double.self) { Text("\(Int(e)) ft") } }
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
    NavigationStack {
        RidesView(
            store: Store(initialState: RidesFeature.State()) { RidesFeature() },
            recordedItems: [],
            onStartRide: {}
        )
    }
    .modelContainer(for: Ride.self, inMemory: true)
}

#Preview("Rides — empty") {
    NavigationStack {
        RidesView(
            store: Store(initialState: RidesFeature.State(demoRides: [])) { RidesFeature() },
            recordedItems: [],
            onStartRide: {}
        )
    }
    .modelContainer(for: Ride.self, inMemory: true)
}

struct RideSummary: Identifiable {
    enum Source { case demo(UUID); case recorded(Ride) }
    let id: String; let title: String; let date: Date
    let elapsedTime: String; let distance: String
    let detail: RideDetail; let source: Source

    static func demo(_ ride: DemoRide) -> RideSummary {
        RideSummary(id: ride.id.uuidString, title: ride.title, date: ride.date,
                    elapsedTime: ride.elapsedTime, distance: ride.distance,
                    detail: ride.detail, source: .demo(ride.id))
    }
    static func recorded(_ ride: Ride) -> RideSummary {
        let detail = RideDetail.recordedRide(timestamp: ride.startedAt)
        return RideSummary(id: ride.id.uuidString,
                           title: detail.title, date: ride.startedAt,
                           elapsedTime: detail.elapsedTime, distance: detail.distance,
                           detail: detail, source: .recorded(ride))
    }
}
