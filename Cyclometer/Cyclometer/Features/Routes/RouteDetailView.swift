import ComposableArchitecture
import MapKit
import SwiftUI

/// S20 — Route Detail, pushed from an S19 row as `RoutesFeature.Path` state (#195).
///
/// The layout is the prototype's that UX.md §S20 points at, now reading a persisted `Route`: the
/// route on a map with its direction of travel, distance and climb, the elevation profile,
/// placeholders for the two sections whose data is not in MVP, and the rides ridden on it.
///
/// This view owns only what a snapshot must not run — the loading and the toolbar. The screen
/// itself is `RouteDetailList`.
struct RouteDetailView: View {
    let store: StoreOf<RouteDetailFeature>
    /// Mirrors Start Ride, which every tab hides while a ride records: "Use This Route" opens the
    /// same sheet, and a second ride cannot begin over the first. `AppFeature` enforces it too.
    var isUseRouteHidden = false

    /// Fixed heights, kept here because the generic `RouteDetailList` cannot hold static stored
    /// properties. The list applies `mapHeight` to whatever map row it is given, so a snapshot's
    /// placeholder takes exactly the live map's footprint.
    static let mapHeight: CGFloat = 220
    static let elevationChartHeight: CGFloat = 120

    var body: some View {
        RouteDetailList(store: store)
            .toolbar {
                if !isUseRouteHidden {
                    ToolbarItem(placement: .topBarTrailing) {
                        // Styled like Start Ride, the other way into the same sheet.
                        Button("Use This Route") { store.send(.useRouteButtonTapped) }
                            .buttonStyle(.bordered)
                            .foregroundStyle(Color.cyPrimary)
                    }
                }
            }
            .task { await store.send(.task).finish() }
    }
}

/// S20's content: everything except the loading and the toolbar, so a snapshot renders it from
/// seeded state without starting a read.
///
/// Generic over the map row for the same reason. A live `Map` renders its tiles asynchronously,
/// and the first render in a process differs from later ones, so it cannot be pixel-snapshotted
/// reproducibly (`RoutesSnapshotTests`). The tests pass a placeholder of the same height, and the
/// reference pins everything around it.
struct RouteDetailList<MapRow: View>: View {
    let store: StoreOf<RouteDetailFeature>
    let mapRow: MapRow

    var body: some View {
        let unit = store.unitSystem
        List {
            Section {
                mapRow
                    .frame(height: RouteDetailView.mapHeight)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerMd, style: .continuous))
                    .listRowInsets(EdgeInsets())
                LabeledContent("Distance", value: distanceLabel(store.summary.distanceMeters, unit))
            }
            // The whole section goes for a route with no `<ele>` — that varies per route, and a
            // header over nothing is noise. The chart is gated separately: a polyline that could
            // not be decoded still leaves the stored gain and loss worth showing.
            if let gain = store.summary.elevationGainMeters {
                Section("Elevation Profile") {
                    if let profile = store.elevationProfileMeters {
                        ElevationProfileView(samples: profile.map(unit.elevation(fromMeters:)),
                                             unitLabel: unit.elevationLabel)
                            .frame(height: RouteDetailView.elevationChartHeight)
                            .padding(.vertical, Spacing.sm)
                    }
                    LabeledContent("Elevation Gain", value: elevationLabel(gain, unit))
                    if let loss = store.summary.elevationLossMeters {
                        LabeledContent("Elevation Loss", value: elevationLabel(loss, unit))
                    }
                }
            }
            // Live weather is WeatherKit, M10.6 (#204); Strava segments need Accounts, Phase 2.
            // Both keep their place in the layout and say plainly that nothing is missing by mistake.
            Section("Current Weather") {
                comingSoon
            }
            Section("Strava Segments") {
                LabeledContent("Connect Strava") { comingSoon }
            }
            // Hidden rather than empty for a route never ridden — UX.md §S20.
            if !store.previousRides.isEmpty {
                Section("Previous Rides") {
                    ForEach(store.previousRides) { ride in
                        // UX.md also lists conditions, which arrive with ride weather in M10.6:
                        // nothing writes `Ride.weather` yet.
                        LabeledContent {
                            Text(Int(ride.durationSeconds).formattedElapsed)
                                .font(.subheadline.weight(.semibold))
                        } label: {
                            Text(ride.startedAt, format: .dateTime.month(.abbreviated).day().year())
                        }
                    }
                }
            }
        }
        .navigationTitle(store.summary.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The repo's placeholder idiom — `StartSheetView`'s Route row.
    private var comingSoon: some View {
        Text("Coming Soon").foregroundStyle(Color.cyTextSecondary)
    }
}

extension RouteDetailList where MapRow == RouteDetailMap {
    init(store: StoreOf<RouteDetailFeature>) {
        self.init(store: store, mapRow: RouteDetailMap(summary: store.summary, coordinates: store.coordinates))
    }
}

/// S20's map: the route with its start and finish flags and direction-of-travel chevrons, framed
/// on the route.
///
/// Pan and zoom only, for the chevrons' sake, as on S19's map: `Annotation` content is
/// screen-space and does not counter-rotate, so under rotation every arrow would point wrong, and
/// a pitched camera's region runs to the horizon and would space them for the wrong viewport.
/// That is why the prototype's `MapPitchToggle` is gone.
struct RouteDetailMap: View {
    let summary: RouteSummary
    let coordinates: [RouteCoordinate]

    /// What the camera shows. The chevrons space themselves from it, and nil means none at all.
    @State private var visibleBounds: RouteBounds?

    /// Padded and floored around the route's stored bounds, so it is ready before the polyline is.
    private var framing: MKCoordinateRegion {
        RoutesMapCamera.region(riderCoordinate: nil, routes: [summary])
    }

    var body: some View {
        Map(initialPosition: .region(framing), interactionModes: [.pan, .zoom]) {
            RouteMapContent(coordinates: coordinates, startTitle: "Start", finishTitle: "Finish",
                            visibleBounds: visibleBounds)
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        // Seeded, because `.onMapCameraChange` is not guaranteed to fire on the first settle —
        // without this the route would open with no direction shown until the rider panned.
        // S19's map seeds for the same reason.
        .onAppear { visibleBounds = RoutesMapCamera.bounds(for: framing) }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleBounds = RoutesMapCamera.bounds(for: context.region)
        }
    }
}

// MARK: - Previews

#Preview("Route Detail — climb, ridden") {
    withDependencies {
        $0.defaultFileStorage = .inMemory
    } operation: {
        let route = RouteSummary.previewRoutes[1]
        return NavigationStack {
            RouteDetailView(store: Store(initialState: RouteDetailFeature.State(summary: route)) {
                RouteDetailFeature()
            } withDependencies: {
                $0.persistenceClient = .mock(routeDetails: RouteDetail.previewRouteDetails,
                                             ridesByRoute: [route.id: RouteRideSummary.previewRides])
            })
        }
    }
}

/// "Coffee Spin" carries no `<ele>` and has never been ridden, so both conditional sections are gone.
#Preview("Route Detail — no elevation, never ridden") {
    withDependencies {
        $0.defaultFileStorage = .inMemory
    } operation: {
        let route = RouteSummary.previewRoutes[3]
        return NavigationStack {
            RouteDetailView(store: Store(initialState: RouteDetailFeature.State(summary: route)) {
                RouteDetailFeature()
            } withDependencies: {
                $0.persistenceClient = .mock(routeDetails: RouteDetail.previewRouteDetails)
            })
        }
    }
}
