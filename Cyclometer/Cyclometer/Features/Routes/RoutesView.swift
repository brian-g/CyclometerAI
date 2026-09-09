import SwiftUI
import MapKit
import ComposableArchitecture
import CoreLocation
import UniformTypeIdentifiers

/// S19 — Route Management.
///
/// Rows do not navigate yet: the detail screen below is still the fake-data prototype that
/// UX.md §S20 points at as its layout spec, and #195 replaces it with a real one.
struct RoutesView: View {
    @Bindable var store: StoreOf<RoutesFeature>
    /// Start Ride is the global toolbar affordance every tab opts into, but items in
    /// *separate* `.toolbar` modifiers sort by ancestry — the outermost lands leftmost, no
    /// matter where in the chain it is applied — so `.startRideToolbarItem` would always put
    /// it first. Declared inside this screen's own toolbar instead, where written order
    /// holds, giving Import, Map/List, Start Ride.
    var isStartRideHidden: Bool = false
    var onStartRide: () -> Void = {}

    /// Resolved from the app's own `UTImportedTypeDeclarations` (`Info.plist`). iOS does
    /// **not** know GPX on its own — measured on iOS 26, `UTType("com.topografix.gpx")` is
    /// nil and `UTType(filenameExtension: "gpx")` answers a *dynamic* type conforming to
    /// nothing, which greys out every `.gpx` in the picker. `RoutesGPXTypeTests` pins the
    /// declaration, since removing it breaks the picker with no compile or runtime error.
    private static let gpxContentTypes: [UTType] = {
        guard let gpx = UTType("com.topografix.gpx"), !gpx.isDynamic else {
            // Reached only if the declaration is gone. `.xml` would be no help — the
            // measurement above is that an undeclared `.gpx` conforms to nothing — so fall
            // back to showing everything rather than a picker where nothing is selectable.
            return [.item]
        }
        return [gpx]
    }()

    var body: some View {
        Group {
            if store.showsMap {
                RoutesMapView(routes: store.routes,
                              polylines: store.polylines,
                              riderCoordinate: store.riderCoordinate)
            } else if store.hasLoaded && store.routes.isEmpty {
                ContentUnavailableView {
                    Label("No Routes", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                } description: {
                    Text("Import a route from the Files app to ride it.")
                } actions: {
                    Button("Import Route") { store.send(.importButtonTapped) }
                        .disabled(store.isImporting)
                }
            } else {
                List(store.routes) { route in
                    RouteRow(route: route, unitSystem: store.unitSystem)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                store.send(.deleteButtonTapped(route.id))
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .navigationTitle("Routes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.send(.importButtonTapped)
                } label: {
                    if store.isImporting {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
                .disabled(store.isImporting)
                .accessibilityLabel("Import Route")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.send(.mapToggled)
                } label: {
                    Image(systemName: store.showsMap ? "list.bullet" : "map")
                }
                .accessibilityLabel(store.showsMap ? "Show as List" : "Show on Map")
            }
            if !isStartRideHidden {
                ToolbarItem(placement: .topBarTrailing) {
                    StartRideButton(action: onStartRide)
                }
            }
        }
        .fileImporter(
            isPresented: $store.isImporterPresented.sending(\.importerPresentationChanged),
            allowedContentTypes: Self.gpxContentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { store.send(.fileSelected(url)) }
            case .failure:
                store.send(.filePickerFailed)
            }
        }
        .alert($store.scope(state: \.alert, action: \.alert))
        .task { await store.send(.task).finish() }
    }
}

private struct RouteRow: View {
    let route: RouteSummary
    let unitSystem: UnitSystem

    /// The terrain line, when the file gave one. Distance used to live here too; it now sits
    /// on the trailing edge as a `HeroNumber`, matching `RideRow`.
    private var terrain: String? {
        guard let terrain = route.terrainDescription, !terrain.isEmpty else { return nil }
        return terrain
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "map")
                .font(.headline)
                .foregroundStyle(.cyPrimary)
                .frame(width: Spacing.xxl, height: Spacing.xxl)
                .background(Color.cyPrimary.opacity(Opacity.iconTile),
                            in: RoundedRectangle(cornerRadius: Spacing.cornerMd, style: .continuous))
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(route.name).font(.headline)
                if let terrain {
                    Text(terrain).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Spacing.sm)
            HeroNumber(unitSystem.distance(fromMeters: route.distanceMeters),
                       unit: unitSystem.distanceLabel)
                .heroNumberSize(.small)
                .layout(.horizontal)
        }
        .padding(.vertical, Spacing.xs)
    }
}

private struct RoutesMapView: View {
    let routes: [RouteSummary]
    let polylines: [UUID: [RouteCoordinate]]
    let riderCoordinate: Coordinate?

    /// The camera is chosen once when the map opens, and the rider is free to pan away
    /// afterwards — but the rider's fix arrives asynchronously and often *after* this view
    /// appears (the tab remembers `showsMap`, so returning to it re-shows the map with no
    /// fix yet). A plain `initialPosition` would ignore that answer and leave the map framed
    /// on route bounds, which is not the 50-mile radius UX.md §S19 asks for. Hence a binding
    /// re-seeded exactly once, when the first fix lands.
    @State private var position: MapCameraPosition?
    @State private var hasCenteredOnRider = false

    var body: some View {
        Map(position: Binding(
            get: { position ?? .region(RoutesMapCamera.region(riderCoordinate: riderCoordinate,
                                                              routes: routes)) },
            set: { position = $0 }
        )) {
            UserAnnotation()
            ForEach(routes) { route in
                // The polylines arrive after the routes do, so a marker draws either way
                // and the route lines fill in when their fetch lands.
                if let coordinates = polylines[route.id], !coordinates.isEmpty {
                    MapPolyline(coordinates: coordinates.map(\.coordinate2D))
                        .stroke(.cyPrimary, lineWidth: 4)
                }
                Marker(route.name, systemImage: "flag.fill",
                       coordinate: markerCoordinate(for: route))
                    .tint(.cyPrimary)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapUserLocationButton(); MapCompass(); MapScaleView()
        }
        .onChange(of: riderCoordinate) { _, fix in
            // Once only: after this the camera belongs to the rider's gestures.
            guard let fix, !hasCenteredOnRider else { return }
            hasCenteredOnRider = true
            position = .region(RoutesMapCamera.region(riderCoordinate: fix, routes: routes))
        }
    }

    /// The route's first point once its polyline is loaded; until then the centre of the
    /// bounding box `RouteSummary` already carries, so every route has a pin immediately.
    private func markerCoordinate(for route: RouteSummary) -> CLLocationCoordinate2D {
        if let first = polylines[route.id]?.first { return first.coordinate2D }
        let center = route.bounds.center
        return CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude)
    }
}

/// The bridge lives here, not on `RouteCoordinate`: the route models import Foundation only,
/// keeping CoreLocation out of the layer that does the geometry arithmetic.
private extension RouteCoordinate {
    var coordinate2D: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

#Preview("Routes — List") {
    NavigationStack {
        RoutesView(store: Store(initialState: RoutesFeature.State()) {
            RoutesFeature()
        } withDependencies: {
            $0.persistenceClient = .mock(routes: RouteSummary.previewRoutes)
        })
    }
}

#Preview("Routes — Empty") {
    NavigationStack {
        RoutesView(store: Store(initialState: RoutesFeature.State()) { RoutesFeature() })
    }
}

#Preview("Routes — Map") {
    NavigationStack {
        RoutesView(store: Store(initialState: RoutesFeature.State(showsMap: true)) {
            RoutesFeature()
        } withDependencies: {
            $0.persistenceClient = .mock(routes: RouteSummary.previewRoutes)
        })
    }
}

#Preview("Route Detail — S20 prototype") {
    NavigationStack {
        RouteDetailView(route: RouteStub.sampleRoutes[0])
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
