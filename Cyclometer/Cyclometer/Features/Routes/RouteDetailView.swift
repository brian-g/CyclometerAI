import ComposableArchitecture
import MapKit
import SwiftUI

/// S20 — Route Detail, pushed from an S19 row as `RideRoutePath` state (#195), or from S15's Route
/// row on the Rides tab (#426).
///
/// The layout is the prototype's that UX.md §S20 points at, now reading a persisted `Route`: the
/// route on a map with its direction of travel, distance and climb, the elevation profile, the
/// weather at its start (#204), a placeholder for Strava segments (Phase 2), and the rides ridden
/// on it.
///
/// This view owns only what a snapshot must not run — the loading, the clock and the toolbar. The
/// screen itself is `RouteDetailList`.
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
        // Once a minute, as W10's sheet: the forecast strip's "Now" moves on the hour while S20
        // stays up (#204).
        TimelineView(.everyMinute) { context in
            RouteDetailList(store: store, now: context.date)
        }
            .toolbar {
                if !isUseRouteHidden {
                    ToolbarItem(placement: .topBarTrailing) {
                        // Styled like Start Ride, the other way into the same sheet.
                        Button("Use Route") { store.send(.useRouteButtonTapped) }
                            .buttonStyle(.bordered)
                            .foregroundStyle(Color.cyPrimary)
                    }
                }
            }
            .task { await store.send(.task).finish() }
    }
}

/// S20's content: everything except the loading, the clock and the toolbar, so a snapshot renders
/// it from seeded state at a fixed time without starting a read.
///
/// Generic over the map row for the same reason. A live `Map` renders its tiles asynchronously,
/// and the first render in a process differs from later ones, so it cannot be pixel-snapshotted
/// reproducibly (`RoutesSnapshotTests`). The tests pass a placeholder of the same height, and the
/// reference pins everything around it.
struct RouteDetailList<MapRow: View>: View {
    let store: StoreOf<RouteDetailFeature>
    let mapRow: MapRow
    /// The clock the weather's strip is read against.
    let now: Date

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
            RouteSummarySection(summary: store.summary, unit: unit)
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
            // Called in this body, so it tracks the fields it reads; never handed down as a
            // snapshot (lessons, #537).
            RouteWeatherSection(weather: store.weather, hours: store.state.forecastHours(at: now),
                                now: now, unit: unit)
            // Strava segments need Accounts, Phase 2. The section keeps its place in the layout
            // and says plainly that nothing is missing by mistake.
            Section("Strava Segments") {
                LabeledContent("Connect Strava") { comingSoon }
            }
            // Hidden rather than empty for a route never ridden — UX.md §S20.
            if !store.previousRides.isEmpty {
                Section("Previous Rides") {
                    ForEach(store.previousRides) { ride in
                        // Opens S15 on whichever tab's stack S20 is on (#426).
                        NavigationLink(state: RideRoutePath.State.ride(RideDetailFeature.State(summary: RideListSummary(ride)))) {
                            LabeledContent {
                                Text(Int(ride.durationSeconds).formattedElapsed)
                                    .font(.subheadline.weight(.semibold))
                            } label: {
                                Text(ride.startedAt, format: .dateTime.month(.abbreviated).day().year())
                                PreviousRideConditions(summary: RideWeatherSummary(samples: ride.weather, exposure: nil))
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(store.summary.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The repo's placeholder idiom for a section whose data is not in MVP yet.
    private var comingSoon: some View {
        Text("Coming Soon").foregroundStyle(Color.cyTextSecondary)
    }
}

extension RouteDetailList where MapRow == RouteDetailMap {
    init(store: StoreOf<RouteDetailFeature>, now: Date) {
        self.init(store: store, mapRow: RouteDetailMap(summary: store.summary, coordinates: store.coordinates), now: now)
    }
}

/// A Previous Rides row's second line (#204): the sky the ride saw most and its temperature range,
/// "Partly Cloudy · 14–18 °C", in the locale's weather unit as S15 quotes it. Nothing for a ride
/// with no conditions recorded.
///
/// Words rather than a symbol: the samples don't record whether the sun was up, so a night ride
/// would get a sun.
private struct PreviousRideConditions: View {
    let summary: RideWeatherSummary

    @Environment(\.locale) private var locale

    var body: some View {
        if let temperature = summary.temperature(in: UnitTemperature(forLocale: locale, usage: .weather)) {
            Group {
                if let condition = summary.prevailingCondition {
                    Text("\(condition.displayName) · \(temperature.shown)")
                        .accessibilityLabel("\(condition.displayName), \(temperature.spoken)")
                } else {
                    Text("\(temperature.shown)")
                        .accessibilityLabel(temperature.spoken)
                }
            }
            .font(.subheadline)
            .foregroundStyle(Color.cyTextSecondary)
            .monospacedDigit()
        }
    }
}

/// S20's map: the route with its start and finish flags and direction-of-travel arrows, framed
/// on the route.
///
/// Pan and zoom only, for the arrows' sake, as on S19's map: a pitched or rotated camera's region
/// is wider than the screen — pitched, it runs to the horizon — and would space them for the wrong
/// viewport. That is why the prototype's `MapPitchToggle` is gone.
struct RouteDetailMap: View {
    let summary: RouteSummary
    let coordinates: [RouteCoordinate]

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
                                arrows: arrows, metersPerPoint: metersPerPoint)
            }
            .mapStyle(.standard(elevation: .realistic))
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

    private func placeArrows() {
        arrows = RouteDirectionMarkers.arrows(coordinates: coordinates, visibleBounds: visibleBounds)
    }
}

// MARK: - Previews

/// S20 already pushed on the Routes tab's own stack, as the app hosts it: a Previous Rides row is a
/// `NavigationLink(state:)`, which reports "not presentable" in a plain `NavigationStack` (#426).
private func routeDetailPreview(_ route: RouteSummary, persistenceClient: PersistenceClient,
                                weatherClient: WeatherClient = .previewAtNow,
                                networkStatus: NetworkStatusClient = .previewValue) -> some View {
    withDependencies {
        $0.defaultFileStorage = .inMemory
    } operation: {
        var state = RoutesFeature.State()
        state.path.append(.route(RouteDetailFeature.State(summary: route)))
        return RoutesNavigationStack(store: Store(initialState: state) {
            RoutesFeature()
        } withDependencies: {
            $0.persistenceClient = persistenceClient
            $0.weatherClient = weatherClient
            $0.networkStatus = networkStatus
        })
    }
}

private extension WeatherClient {
    /// The fixture forecast moved to the real clock: S20's strip reads the hours from it, and the
    /// fixture's fixed date would leave none.
    static let previewAtNow = WeatherClient(
        current: { _ in AttributedForecast.fixture(at: Date()).current },
        forecast: { _ in
            let forecast = AttributedForecast.fixture(at: Date())
            return WeatherForecast(current: forecast.current, hourly: forecast.hourly)
        },
        attribution: { .fixture }
    )
}

#Preview("Route Detail — climb, ridden") {
    let route = RouteSummary.previewRoutes[1]
    routeDetailPreview(route, persistenceClient: .mock(
        routes: RouteSummary.previewRoutes,
        routeDetails: RouteDetail.previewRouteDetails,
        ridesByRoute: [route.id: RouteRideSummary.previewRides]
    ))
}

/// "Coffee Spin" carries no `<ele>` and has never been ridden, so both conditional sections are gone.
#Preview("Route Detail — no elevation, never ridden") {
    routeDetailPreview(RouteSummary.previewRoutes[3], persistenceClient: .mock(
        routes: RouteSummary.previewRoutes,
        routeDetails: RouteDetail.previewRouteDetails
    ))
}

#Preview("Route Detail — offline") {
    let route = RouteSummary.previewRoutes[1]
    routeDetailPreview(route, persistenceClient: .mock(
        routes: RouteSummary.previewRoutes,
        routeDetails: RouteDetail.previewRouteDetails,
        ridesByRoute: [route.id: RouteRideSummary.previewRides]
    ), weatherClient: .unavailable, networkStatus: .offline)
}
