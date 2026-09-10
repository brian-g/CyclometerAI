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
    /// holds, giving Import, Filter, Map/List, Start Ride.
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
                mapView
            } else if store.hasLoaded && store.routes.isEmpty {
                emptyLibrary
            } else {
                VStack(spacing: 0) {
                    if store.isFiltered {
                        FilterStatusBar(
                            shownCount: store.filteredRoutes.count,
                            totalCount: store.routes.count,
                            showsMapChip: store.mapFilterBounds != nil,
                            onClearMapFilter: { store.send(.mapFilterCleared) }
                        )
                    }
                    // Three empty states, kept distinct on purpose: not read yet renders a
                    // blank list, nothing saved is `emptyLibrary` above, and nothing *matching*
                    // is this. Collapsing the last two would tell a rider who filtered too hard
                    // that their routes are gone.
                    if store.hasLoaded && store.filteredRoutes.isEmpty {
                        noMatches
                    } else {
                        routeList
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
            // Hidden with nothing saved: the sliders derive their travel from the routes, so
            // an empty library would open a sheet of dead controls beside "No Routes".
            if !store.routes.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    filterButton
                }
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
        .sheet(isPresented: $store.isFilterSheetPresented.sending(\.filterSheetPresentationChanged)) {
            RouteFilterSheet(store: store)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .alert($store.scope(state: \.alert, action: \.alert))
        .task { await store.send(.task).finish() }
    }

    // MARK: - Branches

    private var routeList: some View {
        List(store.filteredRoutes) { route in
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

    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label("No Routes", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
        } description: {
            Text("Import a route from the Files app to ride it.")
        } actions: {
            Button("Import Route") { store.send(.importButtonTapped) }
                .disabled(store.isImporting)
        }
    }

    private var noMatches: some View {
        ContentUnavailableView {
            Label("No Matching Routes", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text(store.mapFilterBounds == nil
                 ? "No saved route matches the current filters."
                 : "No saved route matches the current filters in this map area.")
        } actions: {
            // Only the sheet's filters. The map narrowing is cleared from its own chip above,
            // which stays on screen behind this view — one button clearing both would make the
            // badge's promise about what it covers untrue.
            if store.activeFilterCount > 0 {
                Button("Clear Filters") { store.send(.filtersCleared) }
            }
        }
    }

    private var mapView: some View {
        RoutesMapView(
            routes: store.sheetFilteredRoutes,
            allRoutes: store.routes,
            polylines: store.polylines,
            riderCoordinate: store.riderCoordinate,
            storedViewport: store.visibleMapBounds,
            onRegionChanged: { store.send(.mapRegionChanged($0)) }
        )
        .overlay {
            // The map branch short-circuits both list empty states, so without this a sheet
            // filter matching nothing leaves a blank map and no way to find out why.
            if store.hasLoaded && !store.routes.isEmpty && store.sheetFilteredRoutes.isEmpty {
                ContentUnavailableView {
                    Label("No Matching Routes", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("No saved route matches the current filters.")
                } actions: {
                    Button("Clear Filters") { store.send(.filtersCleared) }
                }
                .background(.regularMaterial)
            }
        }
    }

    private var filterButton: some View {
        Button {
            store.send(.filterButtonTapped)
        } label: {
            Image(systemName: store.activeFilterCount > 0
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
                .overlay(alignment: .topTrailing) {
                    if store.activeFilterCount > 0 {
                        Text("\(store.activeFilterCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.cyTextOnPrimary)
                            .frame(width: Spacing.lg, height: Spacing.lg)
                            .background(Color.cyPrimary, in: Circle())
                            .offset(x: Spacing.sm, y: -Spacing.sm)
                    }
                }
        }
        .accessibilityLabel("Filter Routes")
        // Without this the badge reads to VoiceOver as a stray number beside an icon.
        .accessibilityValue(store.activeFilterCount == 0
                            ? "No filters active"
                            : (store.activeFilterCount == 1 ? "1 filter active"
                                                            : "\(store.activeFilterCount) filters active"))
    }
}

// MARK: - Filter status

/// Why the list is shorter than the library. The issue asks the list to say plainly that it is
/// filtered — "my route vanished" and "this is a bug" are otherwise the same experience.
private struct FilterStatusBar: View {
    let shownCount: Int
    let totalCount: Int
    let showsMapChip: Bool
    let onClearMapFilter: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text("\(shownCount) of \(totalCount) routes")
                .font(.footnote)
                .foregroundStyle(Color.cyTextSecondary)
            Spacer(minLength: Spacing.sm)
            if showsMapChip {
                Button(action: onClearMapFilter) {
                    HStack(spacing: Spacing.xs) {
                        Text("In map area").font(.footnote.weight(.medium))
                        Image(systemName: "xmark.circle.fill").font(.footnote)
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .foregroundStyle(Color.cyPrimary)
                    .background(Color.cyPrimary.opacity(Opacity.iconTile), in: Capsule())
                }
                .buttonStyle(.plain)
                // The chip is the only affordance that explains a map narrowing, so its clear
                // must announce as more than "x".
                .accessibilityLabel("Clear map filter")
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: .infinity)
        .background(Color.cyBgSecondary)
    }
}

// MARK: - Filter sheet

/// Wrapper only. The content is `RouteFilterSheetBody` because a sheet carrying
/// `.topBarLeading`/`.topBarTrailing` toolbar items renders blank inside a
/// `UIHostingController`, which is what a snapshot test uses
/// (`StartSheetSnapshotTests.swift:6-13`).
private struct RouteFilterSheet: View {
    @Bindable var store: StoreOf<RoutesFeature>

    var body: some View {
        NavigationStack {
            RouteFilterSheetBody(store: store)
                .navigationTitle("Filter Routes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { store.send(.filterSheetPresentationChanged(false)) }
                    }
                }
        }
    }
}

struct RouteFilterSheetBody: View {
    @Bindable var store: StoreOf<RoutesFeature>

    var body: some View {
        Form {
            if let domain = store.filterDomain {
                Section("Distance") {
                    distanceRow(domain)
                }
                // Hidden rather than empty when no saved route carries an elevation: a GPX
                // library exported without `<ele>` is ordinary, and a slider with nothing
                // behind it invites a filter that cannot do anything.
                if let gainRange = domain.elevationGain, let gainStep = domain.elevationGainStep {
                    Section("Elevation Gain") {
                        gainRow(range: gainRange, step: gainStep)
                    }
                }
            }
            Section {
                Button("Clear Filters") { store.send(.filtersCleared) }
                    .disabled(store.activeFilterCount == 0)
            }
        }
    }

    private func distanceRow(_ domain: RouteFilterDomain) -> some View {
        // Nil means unset, which on the sliders is the domain at full width.
        let range = store.filter.distanceMeters ?? domain.distance
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            valueLabels(leading: distanceText(range.lowerBound),
                        trailing: distanceText(range.upperBound))
            RangeSlider(
                lowerValue: Binding(
                    get: { range.lowerBound },
                    set: { store.send(.distanceFilterChanged(min($0, range.upperBound)...range.upperBound)) }
                ),
                upperValue: Binding(
                    get: { range.upperBound },
                    set: { store.send(.distanceFilterChanged(range.lowerBound...max($0, range.lowerBound))) }
                ),
                in: domain.distance,
                step: domain.distanceStep,
                lowerLabel: "Minimum distance",
                upperLabel: "Maximum distance",
                format: distanceText
            )
        }
        .padding(.vertical, Spacing.xs)
    }

    private func gainRow(range: ClosedRange<Double>, step: Double) -> some View {
        let maximum = store.filter.maxElevationGainMeters ?? range.upperBound
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            valueLabels(leading: "Up to", trailing: elevationText(maximum))
            RangeSlider(
                upperValue: Binding(
                    get: { maximum },
                    set: { store.send(.elevationGainFilterChanged($0)) }
                ),
                in: range,
                step: step,
                label: "Maximum elevation gain",
                format: elevationText
            )
            Text("Routes with no elevation data are always shown.")
                .font(.caption)
                .foregroundStyle(Color.cyTextSecondary)
        }
        .padding(.vertical, Spacing.xs)
    }

    /// Side by side while they fit, stacked once Dynamic Type makes them collide.
    private func valueLabels(leading: String, trailing: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(leading)
                Spacer(minLength: Spacing.sm)
                Text(trailing)
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(leading)
                Text(trailing)
            }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Color.cyTextPrimary)
    }

    private func distanceText(_ meters: Double) -> String {
        let unit = store.unitSystem
        let value = unit.distance(fromMeters: meters)
        return "\(value.formatted(.number.precision(.fractionLength(1)))) \(unit.distanceLabel)"
    }

    private func elevationText(_ meters: Double) -> String {
        let unit = store.unitSystem
        let value = unit.elevation(fromMeters: meters)
        return "\(value.formatted(.number.precision(.fractionLength(0)))) \(unit.elevationLabel)"
    }
}

// MARK: - Rows and map

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
    /// What to draw — the sheet-filtered set, so the map and the list agree about distance and
    /// gain while the map still shows everything outside the captured viewport.
    let routes: [RouteSummary]
    /// Everything saved. Framing and the "this viewport excludes nothing" test both read this
    /// rather than `routes`, so changing a slider cannot move the camera.
    let allRoutes: [RouteSummary]
    let polylines: [UUID: [RouteCoordinate]]
    let riderCoordinate: Coordinate?
    /// Where the rider left the map last time. Restoring it is what stops the map filter from
    /// re-capturing a viewport nobody chose.
    let storedViewport: RouteBounds?
    let onRegionChanged: (RouteBounds?) -> Void

    /// This view is torn down and rebuilt on every list/map toggle, because it lives inside an
    /// `if store.showsMap`. Before the seed below, that meant re-opening the map re-framed on
    /// the rider — so panning to another city, switching to the list and back silently replaced
    /// the captured viewport with the rider's own region, changing the filter with no gesture.
    @State private var position: MapCameraPosition?
    @State private var visibleBounds: RouteBounds?
    @State private var restoredStoredViewport = false
    @State private var hasCenteredOnRider = false

    private var seedRegion: MKCoordinateRegion {
        if let storedViewport { return RoutesMapCamera.region(for: storedViewport) }
        return RoutesMapCamera.region(riderCoordinate: riderCoordinate, routes: allRoutes)
    }

    var body: some View {
        Map(
            position: Binding(get: { position ?? .region(seedRegion) }, set: { position = $0 }),
            // Pitch and rotation are both off, and both for the filter's sake.
            // `MapCameraUpdateContext.region` is the axis-aligned box around the visible
            // *frustum*: pitched, it runs to the horizon and would match nearly every saved
            // route while the screen showed a narrow wedge. Rotation is the chevrons' problem —
            // `Annotation` content is screen-space and does not counter-rotate, so every arrow
            // would point wrong. A route-browsing map loses nothing by dropping them.
            interactionModes: [.pan, .zoom]
        ) {
            UserAnnotation()
            ForEach(routes) { route in
                if let coordinates = polylines[route.id], !coordinates.isEmpty {
                    RouteMapContent(coordinates: coordinates,
                                    startTitle: route.name,
                                    visibleBounds: visibleBounds)
                } else {
                    // Geometry arrives after the routes do, so a pin stands in until it lands.
                    Marker(route.name, systemImage: "flag.fill",
                           coordinate: markerCoordinate(for: route))
                        .tint(.cyPrimary)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapUserLocationButton(); MapCompass(); MapScaleView()
        }
        .onAppear {
            guard position == nil else { return }
            restoredStoredViewport = storedViewport != nil
            let region = seedRegion
            position = .region(region)
            // Reported explicitly rather than waiting on `.onMapCameraChange`: if that does not
            // fire on the first settle, the captured viewport would be nil and the map filter
            // would silently never apply.
            report(region)
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            report(context.region)
        }
        .onChange(of: riderCoordinate) { _, fix in
            // Only on a first-ever open, and only once: after this the camera belongs to the
            // rider's gestures, and a restored viewport outranks a late-arriving fix.
            guard let fix, !restoredStoredViewport, !hasCenteredOnRider else { return }
            hasCenteredOnRider = true
            let region = RoutesMapCamera.region(riderCoordinate: fix, routes: allRoutes)
            position = .region(region)
            report(region)
        }
    }

    /// The chevrons need the raw viewport whatever it holds; the filter is absent when the
    /// viewport already shows everything. Two answers, so two calls.
    private func report(_ region: MKCoordinateRegion) {
        visibleBounds = RoutesMapCamera.bounds(for: region)
        onRegionChanged(RoutesMapCamera.filterBounds(for: region, routes: allRoutes))
    }

    /// The route's first point once its polyline is loaded; until then the centre of the
    /// bounding box `RouteSummary` already carries, so every route has a pin immediately.
    private func markerCoordinate(for route: RouteSummary) -> CLLocationCoordinate2D {
        if let first = polylines[route.id]?.first { return first.coordinate2D }
        let center = route.bounds.center
        return CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude)
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

/// Geometry included, so the map draws real polylines with their direction chevrons and end
/// flags rather than the bare pins a summary-only mock produces. "River Loop" is closed, which
/// is the case `RouteMapContent` collapses to a single flag.
#Preview("Routes — Map") {
    NavigationStack {
        RoutesView(store: Store(initialState: RoutesFeature.State(showsMap: true)) {
            RoutesFeature()
        } withDependencies: {
            $0.persistenceClient = .mock(routes: RouteSummary.previewRoutes,
                                         routeDetails: RouteDetail.previewRouteDetails)
        })
    }
}

#Preview("Routes — Filtered list") {
    NavigationStack {
        RoutesView(store: Store(
            initialState: {
                var state = RoutesFeature.State()
                state.routes = RouteSummary.previewRoutes
                state.hasLoaded = true
                state.filter = RouteFilter(distanceMeters: 20_000...40_000,
                                           maxElevationGainMeters: nil)
                state.mapFilterBounds = RouteBounds(minLatitude: 37.30, maxLatitude: 37.40,
                                                    minLongitude: -122.06, maxLongitude: -121.97)
                state.mapFilteredRouteIDs = Set(RouteSummary.previewRoutes.prefix(2).map(\.id))
                return state
            }()
        ) {
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

