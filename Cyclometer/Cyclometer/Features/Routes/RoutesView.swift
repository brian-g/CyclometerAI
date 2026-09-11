import SwiftUI
import MapKit
import ComposableArchitecture
import CoreLocation
import UniformTypeIdentifiers

/// S19 — Route Management. A row pushes S20, `RouteDetailView`, onto the tab's navigation stack
/// as `RoutesFeature.Path` state (#195).
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
                // Read once. `filteredRoutes` walks every route and then a `Set`, and this
                // branch would otherwise ask for it three times per body pass — which is the
                // very cost `mapFilteredRouteIDs` is stored to avoid.
                let shown = store.filteredRoutes
                // Three empty states, kept distinct on purpose: not read yet renders a blank
                // list, nothing saved is `emptyLibrary` above, and nothing *matching* is this.
                // Collapsing the last two would tell a rider who filtered too hard that their
                // routes are gone.
                if store.hasLoaded && shown.isEmpty {
                    VStack(spacing: 0) {
                        filterChips(shown: shown.count)
                        noMatches
                    }
                } else {
                    routeList(shown)
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
            // Gated on the domain, not merely on `routes.isEmpty`: `RouteFilterDomain.from`
            // also answers nil when no route has a finite distance, and the button must not
            // open a sheet whose sliders have no travel to offer.
            if store.filterDomain != nil {
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

    /// The chips ride in the list's own section header rather than in a bar stacked above it.
    /// Stacked, the bar sat outside the list's insets so it never lined up with the rows, and
    /// showing or hiding it resized the list's frame — which is what made it jump. As a header
    /// it takes the list's insets, sticks to the top while the rows scroll under it, and
    /// appearing costs the list nothing.
    private func routeList(_ routes: [RouteSummary]) -> some View {
        List {
            Section {
                ForEach(routes) { route in
                    // Seeded with the summary the row already holds, so S20 has its name,
                    // distance and climb from its first frame and reads only the geometry.
                    NavigationLink(state: RoutesFeature.Path.State.detail(RouteDetailFeature.State(summary: route))) {
                        RouteRow(route: route, unitSystem: store.unitSystem)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            store.send(.deleteButtonTapped(route.id))
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        // `role: .destructive` alone is not enough: the app-wide `.tint`
                        // wins over the role inside a swipe action, so Delete rendered in
                        // the brand green.
                        .tint(Color.cyDestructive)
                    }
                }
            } header: {
                filterChips(shown: routes.count)
            }
        }
    }

    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label("No Routes", systemImage: RouteLibrary.symbolName)
        } description: {
            Text("Import a route from the Files app to ride it.")
        } actions: {
            Button("Import Route") { store.send(.importButtonTapped) }
                .disabled(store.isImporting)
        }
    }

    /// One chip per applied filter, each clearing just itself, plus how much of the library
    /// survives them. The issue asks the list to say plainly that it is filtered — otherwise
    /// "my route vanished" and "this is a bug" are the same experience.
    @ViewBuilder
    private func filterChips(shown: Int) -> some View {
        if store.isFiltered {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    Text("\(shown) of \(store.routes.count)")
                        .font(.footnote)
                        .foregroundStyle(Color.cyTextSecondary)
                        .fixedSize()
                    if let range = store.filter.distanceMeters {
                        FilterChip(label: distanceRangeLabel(range),
                                   accessibilityLabel: "Clear distance filter") {
                            store.send(.distanceFilterCleared)
                        }
                    }
                    if let gain = store.filter.maxElevationGainMeters {
                        FilterChip(label: "≤ " + elevationLabel(gain, store.unitSystem),
                                   accessibilityLabel: "Clear elevation gain filter") {
                            store.send(.elevationGainFilterCleared)
                        }
                    }
                    if store.mapFilterBounds != nil {
                        FilterChip(label: "In map area",
                                   accessibilityLabel: "Clear map filter") {
                            store.send(.mapFilterCleared)
                        }
                    }
                }
                .padding(.vertical, Spacing.xs)
            }
            // Ideal height, not every point offered: left to itself the scroll view claims the
            // whole header and pushes the rows off. It still scrolls sideways once Dynamic Type
            // makes the labels too wide to fit.
            .fixedSize(horizontal: false, vertical: true)
            // A section header is uppercased by default, which would shout the chip labels.
            .textCase(nil)
        }
    }

    private func distanceRangeLabel(_ range: ClosedRange<Double>) -> String {
        let unit = store.unitSystem
        let low = unit.distance(fromMeters: range.lowerBound)
            .formatted(.number.precision(.fractionLength(1)))
        let high = unit.distance(fromMeters: range.upperBound)
            .formatted(.number.precision(.fractionLength(1)))
        return "\(low)–\(high) \(unit.distanceLabel)"
    }

    private var noMatches: some View {
        ContentUnavailableView {
            Label("No Matching Routes", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text(store.mapFilterBounds == nil
                 ? "No saved route matches the current filters."
                 : "No saved route matches the current filters in this map area.")
        } actions: {
            // Everything, the map narrowing included. A rider who has filtered down to nothing
            // wants their library back; clearing only the sheet's two would leave the screen
            // still empty and the reason for it still on.
            Button("Clear Filters") { store.send(.allFiltersCleared) }
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
                    Button("Clear Filters") { store.send(.allFiltersCleared) }
                }
                .background(.regularMaterial)
            }
        }
    }

    private var filterButton: some View {
        Button {
            store.send(.filterButtonTapped)
        } label: {
            // Filled when something is applied, and nothing more. A count badge belongs
            // outside the glyph's bounds, and a toolbar clips its items — the badge was being
            // cut off. The chips above the list carry the detail instead, and say *which*
            // filters are on rather than only how many.
            Image(systemName: store.activeFilterCount > 0
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filter Routes")
        // Without this the badge reads to VoiceOver as a stray number beside an icon.
        .accessibilityValue(store.activeFilterCount == 0
                            ? "No filters active"
                            : (store.activeFilterCount == 1 ? "1 filter active"
                                                            : "\(store.activeFilterCount) filters active"))
    }
}

// MARK: - Navigation stack

/// The Routes tab's navigation stack: S19 at the root, S20 pushed as `RoutesFeature.Path` state
/// (#195). One definition for the app, the previews and the snapshot tests, because a
/// `NavigationLink(state:)` row outside a store-powered stack reports an issue — a failure under
/// XCTest — and cannot push.
struct RoutesNavigationStack: View {
    @Bindable var store: StoreOf<RoutesFeature>
    /// Hides both ways into the Start sheet while a ride records: S19's Start Ride and S20's
    /// Use This Route.
    var isStartRideHidden: Bool = false
    var onStartRide: () -> Void = {}

    var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            RoutesView(store: store, isStartRideHidden: isStartRideHidden, onStartRide: onStartRide)
        } destination: { pathStore in
            switch pathStore.case {
            case .detail(let detailStore):
                RouteDetailView(store: detailStore, isUseRouteHidden: isStartRideHidden)
            }
        }
    }
}

// MARK: - Filter status

/// One applied filter, with its own way out. Used for all three, so a filter set from the
/// sheet and one set by panning the map are cleared the same way.
private struct FilterChip: View {
    let label: String
    let accessibilityLabel: String
    let onClear: () -> Void

    var body: some View {
        Button(action: onClear) {
            HStack(spacing: Spacing.xs) {
                Text(label).font(.footnote.weight(.medium))
                Image(systemName: "xmark.circle.fill").font(.footnote)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .foregroundStyle(Color.cyPrimary)
            .background(Color.cyPrimary.opacity(Opacity.iconTile), in: Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        // The chips are the only thing explaining why rows are missing, so each clear has to
        // announce as more than "x".
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Shared by the chip row, the sheet and S20 (#195), so none of them disagree about how a climb
/// reads.
func elevationLabel(_ meters: Double, _ unit: UnitSystem) -> String {
    let value = unit.elevation(fromMeters: meters)
    return "\(value.formatted(.number.precision(.fractionLength(0)))) \(unit.elevationLabel)"
}

/// The filter sheet's distance format, shared with S20 (#195) for the same reason.
func distanceLabel(_ meters: Double, _ unit: UnitSystem) -> String {
    let value = unit.distance(fromMeters: meters)
    return "\(value.formatted(.number.precision(.fractionLength(1)))) \(unit.distanceLabel)"
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
                Button("Clear All Filters") { store.send(.allFiltersCleared) }
                    .disabled(!store.isFiltered)
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
        distanceLabel(meters, store.unitSystem)
    }

    private func elevationText(_ meters: Double) -> String {
        elevationLabel(meters, store.unitSystem)
    }
}

// MARK: - Rows and map

/// One saved route. Internal so S05.2's picker (#196) draws a route the way S19 does.
struct RouteRow: View {
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
    /// What `onAppear` framed. A late rider fix re-centres only while the camera is still
    /// sitting on it — otherwise a fix that resolves a second after the map opens throws away
    /// a pan the rider has already made and captures a viewport they never chose.
    @State private var seededBounds: RouteBounds?

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
            seededBounds = RoutesMapCamera.bounds(for: region)
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
            guard let fix, !restoredStoredViewport, !hasCenteredOnRider,
                  visibleBounds == seededBounds
            else { return }
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

/// Every preview hosts S19 in `RoutesNavigationStack`, as the app does. In this one a tapped row
/// pushes a fully loaded S20 — geometry for every route, and previous rides for "Summit Climb" —
/// which is the quickest way to look at the route detail map, since no snapshot can pin it.
#Preview("Routes — List") {
    RoutesNavigationStack(store: Store(initialState: RoutesFeature.State()) {
        RoutesFeature()
    } withDependencies: {
        $0.persistenceClient = .mock(
            routes: RouteSummary.previewRoutes,
            routeDetails: RouteDetail.previewRouteDetails,
            ridesByRoute: [RouteSummary.previewRoutes[1].id: RouteRideSummary.previewRides]
        )
    })
}

#Preview("Routes — Empty") {
    RoutesNavigationStack(store: Store(initialState: RoutesFeature.State()) { RoutesFeature() })
}

/// Geometry included, so the map draws real polylines with their direction chevrons and end
/// flags rather than the bare pins a summary-only mock produces. "River Loop" is closed, which
/// is the case `RouteMapContent` collapses to a single flag.
#Preview("Routes — Map") {
    RoutesNavigationStack(store: Store(initialState: RoutesFeature.State(showsMap: true)) {
        RoutesFeature()
    } withDependencies: {
        $0.persistenceClient = .mock(routes: RouteSummary.previewRoutes,
                                     routeDetails: RouteDetail.previewRouteDetails)
    })
}

#Preview("Routes — Filtered list") {
    RoutesNavigationStack(store: Store(
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

