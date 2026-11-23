import ComposableArchitecture
import MapKit
import SwiftUI

/// S20's full-screen map (#570): the route, with pan and zoom. S15's map sheet's shape
/// (`RideMapSheet`): a bar only for the close every sheet carries and the map's options, with no
/// background, so the map runs to the sheet's top edge.
///
/// Its options are one menu, as S15's (#537): the basemap, the forecast wind layer, and what the
/// route is colored by, with a legend at the bottom for Grade.
struct RouteMapSheet: View {
    @Bindable var store: StoreOf<RouteMapSheetFeature>

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Each field read here, from the store, so a change to any of them redraws the map
                // (lessons, #537).
                RouteDetailMap(
                    summary: store.summary,
                    coordinates: store.coordinates,
                    wind: store.showsWind ? store.wind : [],
                    basemap: store.basemap,
                    coloring: store.coloring,
                    coloredRuns: store.coloredRuns
                )
                .ignoresSafeArea(edges: .bottom)
                if !store.legend.isEmpty {
                    RideMapLegend(coloring: store.coloring, unit: store.legendUnit, entries: store.legend)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.bottom, Spacing.sm)
                }
            }
            .sheetCloseButton()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    RouteMapOptionsMenu(store: store)
                }
            }
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

/// The map sheet's options: S15's menu (#537), with the route's layer and colorings. Grade isn't
/// offered for a route with no elevation.
private struct RouteMapOptionsMenu: View {
    @Bindable var store: StoreOf<RouteMapSheetFeature>

    var body: some View {
        Menu {
            Picker("Map", selection: $store.basemap.sending(\.basemapSelected)) {
                ForEach(MapBasemap.allCases) { basemap in
                    Text(basemap.title).tag(basemap)
                }
            }
            .pickerStyle(.inline)
            Section("Show") {
                // Offered with or without a forecast yet: the arrows come when it lands.
                Toggle("Wind", isOn: $store.showsWind.sending(\.windToggled))
            }
            Picker("Color Route By", selection: $store.coloring.sending(\.coloringSelected)) {
                ForEach(store.availableColorings) { coloring in
                    Text(coloring.title).tag(coloring)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Map Options", systemImage: "square.3.layers.3d")
        }
    }
}

/// S20's live map, in the map sheet (#570): the route with its start and finish flags and
/// direction-of-travel arrows, the forecast wind along it (#561), on the chosen basemap and colored
/// as chosen, framed on the route.
///
/// Pan and zoom only, for the arrows' sake, as on S19's map: a pitched or rotated camera's region
/// is wider than the screen — pitched, it runs to the horizon — and would space them for the wrong
/// viewport. That is why S15's sheet's `MapPitchToggle` isn't here.
struct RouteDetailMap: View {
    let summary: RouteSummary
    let coordinates: [RouteCoordinate]
    /// The forecast wind along the route for a ride starting now (#561): empty until it lands, and
    /// with the layer off.
    var wind: [WindSample] = []
    var basemap: MapBasemap = .standard
    var coloring: RouteColoring = .plain
    var coloredRuns: [ColoredRun] = []

    /// What the camera shows. The arrows space themselves from it, and nil means none at all.
    @State private var visibleBounds: RouteBounds?
    /// What one screen point covers on the ground, measured from the map on every camera frame,
    /// so the arrows hold their size through a pinch (#341).
    @State private var metersPerPoint: Double?
    /// The route's arrows, placed for `visibleBounds`. Kept here rather than placed in the map's
    /// content because placing walks the route, and the content is redrawn whenever
    /// `metersPerPoint` changes.
    @State private var arrows = RouteDirectionMarkers.Arrows.none

    /// Padded and floored around the route's stored bounds, so it is ready before the polyline is.
    private var framing: MKCoordinateRegion {
        RoutesMapCamera.region(riderCoordinate: nil, routes: [summary])
    }

    var body: some View {
        MapReader { proxy in
            Map(initialPosition: .region(framing), interactionModes: [.pan, .zoom]) {
                RouteMapContent(coordinates: coordinates, startTitle: "Start", finishTitle: "Finish",
                                arrows: arrows, metersPerPoint: metersPerPoint,
                                coloring: coloring, coloredRuns: coloredRuns)
                WindLayer(samples: wind, metersPerPoint: metersPerPoint)
            }
            .mapStyle(mapStyle)
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .measuresMapScale(proxy, into: $metersPerPoint)
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleBounds = RoutesMapCamera.bounds(for: context.region)
            }
        }
        // Seeded, because `.onMapCameraChange` is not guaranteed to fire on the first settle —
        // without this the route would open with no direction shown until the rider panned.
        // S19's map seeds for the same reason.
        .onAppear { visibleBounds = RoutesMapCamera.bounds(for: framing) }
        // Placed when the viewport settles or the geometry lands — never per frame.
        .onChange(of: visibleBounds, initial: true) { placeArrows() }
        .onChange(of: coordinates) { placeArrows() }
    }

    /// S15's basemaps (#537): both with realistic elevation.
    private var mapStyle: MapStyle {
        switch basemap {
        case .standard: .standard(elevation: .realistic)
        case .hybrid: .hybrid(elevation: .realistic)
        }
    }

    private func placeArrows() {
        arrows = RouteDirectionMarkers.arrows(coordinates: coordinates, visibleBounds: visibleBounds)
    }
}

// MARK: - Previews

private func routeMapPreview(_ coloring: RouteColoring) -> some View {
    let route = RouteSummary.previewRoutes[1]
    let coordinates = RouteDetail.previewRouteDetails[route.id]?.coordinates ?? []
    var state = withDependencies {
        $0.defaultFileStorage = .inMemory
    } operation: {
        RouteMapSheetFeature.State(summary: route, coordinates: coordinates, wind: [
            WindSample(coordinate: coordinates[0], reading: .fixture, distanceMeters: 0),
        ])
    }
    state.coloring = coloring
    state.recolor()
    return Color.clear.sheet(isPresented: .constant(true)) {
        RouteMapSheet(store: Store(initialState: state) {
            RouteMapSheetFeature()
        } withDependencies: {
            $0.defaultFileStorage = .inMemory
        })
    }
}

#Preview("Route map") {
    routeMapPreview(.plain)
}

#Preview("Route map — colored by grade") {
    routeMapPreview(.grade)
}

#Preview("Route map — grade, dark") {
    routeMapPreview(.grade)
        .preferredColorScheme(.dark)
}
