import SwiftUI
import MapKit
import ComposableArchitecture
import CoreLocation

struct RoutesView: View {
    @Bindable var store: StoreOf<RoutesFeature>

    var body: some View {
        Group {
            if store.showsMap {
                RoutesMapView(routes: RouteStub.sampleRoutes)
            } else {
                List(RouteStub.sampleRoutes) { route in
                    NavigationLink {
                        RouteDetailView(route: route)
                    } label: {
                        RouteRow(route: route)
                    }
                }
            }
        }
        .navigationTitle("Routes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.send(.mapToggled)
                } label: {
                    Image(systemName: store.showsMap ? "list.bullet" : "map")
                }
                .accessibilityLabel(store.showsMap ? "Show as List" : "Show on Map")
            }
        }
    }
}

private struct RouteRow: View {
    let route: RouteStub

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "map")
                .font(.headline)
                .foregroundStyle(.cyPrimary)
                .frame(width: 36, height: 36)
                .background(Color.cyPrimary.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(route.name).font(.headline)
                Text(route.detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct RoutesMapView: View {
    let routes: [RouteStub]
    private static let spanMeters: CLLocationDistance = 96_560
    private static let fallbackCenter = CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090)

    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(center: fallbackCenter,
                           latitudinalMeters: spanMeters, longitudinalMeters: spanMeters)
    )

    var body: some View {
        Map(position: $position) {
            UserAnnotation()
            ForEach(routes) { route in
                MapPolyline(coordinates: route.coordinates).stroke(.cyPrimary, lineWidth: 4)
                Marker(route.name, systemImage: "flag.fill", coordinate: route.startCoordinate)
                    .tint(.cyPrimary)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapUserLocationButton(); MapCompass(); MapScaleView()
        }
    }
}

struct RouteDetailView: View {
    let route: RouteStub

    var body: some View {
        List {
            Section {
                RouteMapView(route: route)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                LabeledContent("Distance (mi)", value: route.distance)
            }
            Section("Elevation Profile") {
                ElevationProfileView(samples: route.elevationSamples)
                    .frame(height: 120)
                    .padding(.vertical, 8)
                LabeledContent("Elevation Gain (ft)", value: route.elevationGain)
                LabeledContent("Elevation Loss (ft)", value: route.elevationLoss)
            }
            Section("Current Weather") {
                LabeledContent("Temperature", value: route.currentTemperature)
                LabeledContent("Wind") {
                    WindDirectionView(route: route)
                }
                LabeledContent("Wind Speed (mph)", value: "\(route.windSpeed)")
            }
            Section("Strava Segments") {
                ForEach(route.stravaSegments) { segment in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(segment.name).font(.headline)
                            HStack(spacing: 4) {
                                Text(segment.distance); Text("mi"); Text("• \(segment.bestTime)")
                            }
                            .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(segment.bestTime).font(.headline)
                            Text(segment.bestTimeDate, format: .dateTime.month(.wide).day(.twoDigits))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !route.previousRides.isEmpty {
                Section("Previous Rides") {
                    ForEach(route.previousRides) { ride in
                        LabeledContent {
                            Text(ride.elapsedTime).font(.subheadline.weight(.semibold))
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ride.date)
                                Text(ride.condition).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RouteMapView: View {
    let route: RouteStub

    var body: some View {
        Map(initialPosition: .region(route.mapRegion)) {
            MapPolyline(coordinates: route.coordinates).stroke(Color.cyPrimary, lineWidth: 5)
            Marker("Start", systemImage: "flag.fill", coordinate: route.startCoordinate).tint(.cyPrimary)
            Marker("Finish", systemImage: "flag.checkered", coordinate: route.finishCoordinate).tint(.blue)
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls { MapCompass(); MapScaleView(); MapPitchToggle() }
    }
}

private struct WindDirectionView: View {
    let route: RouteStub
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.up")
                .font(.caption.weight(.semibold))
                .rotationEffect(.degrees(Double(route.windDirectionDegrees)))
            Text("\(route.windCompassDirection) (\(route.windDirectionDegrees)°)")
        }
    }
}
