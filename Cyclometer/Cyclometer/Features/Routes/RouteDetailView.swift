import ComposableArchitecture
import MapKit
import SwiftUI

/// S20 — Route Detail, pushed from an S19 row as `RideRoutePath` state (#195), or from S15's Route
/// row on the Rides tab (#426).
///
/// Laid out as S15 is (#570), after Apple Fitness's workout detail: a map header that runs under the
/// top safe area and fades as the list scrolls, the route's name and distance over the fade, then
/// its Summary (#252), Elevation, the weather for a ride starting now (#204), a placeholder for
/// Strava segments (Phase 2), and the rides ridden on it.
///
/// This view owns only what a snapshot must not run — the loading, the clock — and the screen's
/// measurements. The screen itself is `RouteDetailList`.
struct RouteDetailView: View {
    let store: StoreOf<RouteDetailFeature>
    /// Mirrors Start Ride, which every tab hides while a ride records: "Use Route" opens the same
    /// sheet, and a second ride cannot begin over the first. `AppFeature` enforces it too.
    var isUseRouteHidden = false

    /// The elevation chart's height, kept here because the generic `RouteDetailList` cannot hold
    /// static stored properties.
    static let elevationChartHeight: CGFloat = 120

    var body: some View {
        // The screen's, not the list's: the header is half the screen, and the toolbar's bottom is
        // where the title passes under it (`RideDetailView`).
        GeometryReader { proxy in
            // Once a minute, as W10's sheet: the forecast strip's "Now" moves on the hour while S20
            // stays up (#204).
            TimelineView(.everyMinute) { context in
                RouteDetailList(
                    store: store,
                    now: context.date,
                    screenHeight: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom,
                    toolbarBottom: proxy.safeAreaInsets.top,
                    isUseRouteHidden: isUseRouteHidden
                )
            }
        }
        .task { await store.send(.task).finish() }
    }
}

/// S20's content, rendered from state alone so a snapshot can seed it at a fixed time without
/// starting a read.
///
/// Generic over the map header for the reason `RideDetailList` is: a live `Map` renders its tiles
/// asynchronously, and the first render in a process differs from later ones, so it cannot be
/// pixel-snapshotted reproducibly (`RoutesSnapshotTests`). The tests pass a placeholder.
struct RouteDetailList<MapHeader: View>: View {
    @Bindable var store: StoreOf<RouteDetailFeature>
    /// The clock the weather's strip is read against.
    let now: Date
    /// The full screen's height, safe areas included. Passed in rather than read from the list, so a
    /// snapshot drawn on a tall canvas still sizes the header to a phone.
    let screenHeight: CGFloat
    /// Where the toolbar ends, from the top of the screen: the map frames the route below it, and
    /// the title moves into it once scrolled above it.
    let toolbarBottom: CGFloat
    let isUseRouteHidden: Bool
    let mapHeader: MapHeader

    @State private var isTitleUnderToolbar = false

    init(store: StoreOf<RouteDetailFeature>, now: Date, screenHeight: CGFloat, toolbarBottom: CGFloat,
         isUseRouteHidden: Bool = false, @ViewBuilder mapHeader: () -> MapHeader) {
        self.store = store
        self.now = now
        self.screenHeight = screenHeight
        self.toolbarBottom = toolbarBottom
        self.isUseRouteHidden = isUseRouteHidden
        self.mapHeader = mapHeader()
    }

    /// Room for the header from the first frame, while the polyline loads: every saved route was
    /// imported from a track, so it has one to draw. Only a polyline that could not be decoded
    /// leaves the room empty, the map's own background. Always kept with a map to draw, as S15's
    /// `reservesMapHeader` is: a route of one point has no length, but its map still needs the room.
    private var hasHeader: Bool { drawsMap || store.summary.distanceMeters > 0 }
    /// The map itself, once the polyline has loaded.
    private var drawsMap: Bool { !store.coordinates.isEmpty }
    private var mapHeight: CGFloat { MapHeaderChrome.mapHeight(screenHeight: screenHeight) }

    var body: some View {
        let unit = store.unitSystem
        List {
            Section {
                if hasHeader {
                    MapHeaderTapRow(height: mapHeight, isEnabled: drawsMap) { store.send(.mapTapped) }
                }
                RouteTitleBlock(name: store.summary.name, distanceMeters: store.summary.distanceMeters, unit: unit)
                    .tracksTitleUnderToolbar(toolbarBottom, isUnder: $isTitleUnderToolbar)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            RouteSummarySection(summary: store.summary, unit: unit)
            RouteElevationSection(summary: store.summary, profile: store.elevationProfileMeters, unit: unit)
            // Called in this body, so it tracks the fields it reads; never handed down as a
            // snapshot (lessons, #537).
            RouteWeatherSection(weather: store.weather, hours: store.state.forecastHours(at: now),
                                now: now, unit: unit, windExposure: store.windExposure)
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
        .listSectionSpacing(.compact)
        // The list draws over the map, so its own background is the map's surround instead.
        .scrollContentBackground(.hidden)
        .contentMargins(.top, hasHeader ? 0 : nil, for: .scrollContent)
        .mapHeader(hasHeader: hasHeader, drawsMap: drawsMap, height: mapHeight, toolbarBottom: toolbarBottom,
                   header: mapHeader)
        // The title the next screen's back button carries. The bar shows `principal` instead.
        .navigationTitle(store.summary.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                MapHeaderToolbarTitle(title: store.summary.name, isShown: isTitleUnderToolbar)
            }
            if !isUseRouteHidden {
                ToolbarItem(placement: .topBarTrailing) {
                    // Styled like Start Ride, the other way into the same sheet.
                    Button("Use Route") { store.send(.useRouteButtonTapped) }
                        .buttonStyle(.bordered)
                        .foregroundStyle(Color.cyPrimary)
                }
            }
        }
        .sheet(item: $store.scope(state: \.mapSheet, action: \.mapSheet)) { store in
            RouteMapSheet(store: store)
        }
    }

    /// The repo's placeholder idiom for a section whose data is not in MVP yet.
    private var comingSoon: some View {
        Text("Coming Soon").foregroundStyle(Color.cyTextSecondary)
    }
}

extension RouteDetailList where MapHeader == RouteHeaderMap {
    init(store: StoreOf<RouteDetailFeature>, now: Date, screenHeight: CGFloat, toolbarBottom: CGFloat,
         isUseRouteHidden: Bool = false) {
        self.init(store: store, now: now, screenHeight: screenHeight, toolbarBottom: toolbarBottom,
                  isUseRouteHidden: isUseRouteHidden) {
            RouteHeaderMap(coordinates: store.coordinates)
        }
    }
}

// MARK: - Title block

/// The title over the map's fade (UX.md §S20, #570): the route's name, wrapping, then its distance
/// as a small hero, as S15's title block leads with the ride's.
private struct RouteTitleBlock: View {
    let name: String
    let distanceMeters: Double
    let unit: UnitSystem

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(name)
                .font(.title)
                .accessibilityAddTraits(.isHeader)
            // Value and unit, no label, as on S15; VoiceOver names it.
            HeroNumber(unit.distance(fromMeters: distanceMeters), unit: unit.distanceLabel)
                .heroNumberSize(.small)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Distance")
                .accessibilityValue(unit.spokenDistance(fromMeters: distanceMeters))
                .padding(.top, Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Elevation

/// S20's Elevation section, in S15's shape (#548, #570): the route's profile, then its Ascent,
/// Descent and Steepest as heroes in a grid two columns wide.
///
/// The whole section goes for a route with no `<ele>` — that varies per route, and a header over
/// nothing is noise. The chart is gated separately: a polyline that could not be decoded still
/// leaves the stored gain and loss worth showing.
private struct RouteElevationSection: View {
    let summary: RouteSummary
    let profile: [Double]?
    let unit: UnitSystem

    var body: some View {
        if let gain = summary.elevationGainMeters {
            // The Elevation sheet's formatting, so the route's numbers read as a ride's do.
            let metrics = ElevationMetrics(ascentMeters: gain, descentMeters: summary.elevationLossMeters ?? 0,
                                           steepestClimbPercent: summary.terrain?.maxGradePercent, unit: unit)
            Section("Elevation") {
                if let profile {
                    ElevationProfileView(samples: profile.map(unit.elevation(fromMeters:)),
                                         unitLabel: unit.elevationLabel)
                        .frame(height: RouteDetailView.elevationChartHeight)
                        .padding(.vertical, Spacing.sm)
                }
                ReadingColumns(maxColumns: 2) {
                    ReadingColumn("Ascent", metrics.ascent)
                    if summary.elevationLossMeters != nil {
                        ReadingColumn("Descent", metrics.descent)
                    }
                    // The steepest climbing grade only: the route's analysis floors it at 0 and
                    // keeps no steepest descent (#252).
                    if summary.terrain != nil {
                        ReadingColumn("Steepest", metrics.steepestClimb)
                    }
                }
            }
        }
    }
}

// MARK: - Previous rides

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

// MARK: - Header map

/// S20's map header (#570): the route alone, framed whole, with its start and finish flags and its
/// direction-of-travel arrows (#341), and no panning, zooming or wind. Tapping it opens
/// `RouteMapSheet`, which has all of those.
///
/// Framed tight on the route, as S15's header frames a ride (`RideMapThumbnail.headerRect`), with its
/// margins in points, so a short loop fills the header as a long route does.
struct RouteHeaderMap: View {
    let coordinates: [RouteCoordinate]

    /// What one screen point covers on the ground, so the arrows are sized in points (#341).
    @State private var metersPerPoint: Double?
    /// The route's arrows, placed for what the header shows. Kept here rather than placed in the
    /// map's content because placing walks the route (`RouteDetailMap`).
    @State private var arrows = RouteDirectionMarkers.Arrows.none
    /// What the camera last reported showing. A return to S20 runs `onAppear` again, and a camera
    /// that never moves needn't report again, so the seed mustn't replace what it said.
    @State private var cameraBounds: RouteBounds?

    private var framing: MKMapRect { RideMapThumbnail.headerRect(for: [coordinates]) }

    var body: some View {
        MapReader { proxy in
            Map(initialPosition: .rect(framing), interactionModes: []) {
                RouteMapContent(coordinates: coordinates, startTitle: "Start", finishTitle: "Finish",
                                arrows: arrows, metersPerPoint: metersPerPoint)
            }
            .mapStyle(.standard(elevation: .realistic))
            .measuresMapScale(proxy, into: $metersPerPoint)
            // The camera doesn't move, but what it shows is wider than the route's rect: the
            // header is taller than the route, and padded.
            .onMapCameraChange(frequency: .onEnd) { context in
                cameraBounds = RoutesMapCamera.bounds(for: context.region)
                placeArrows(cameraBounds)
            }
        }
        // Room for the start and finish flags, whose balloons stand above their points, and for
        // the route's stroke at the sides — `RideHeaderMap`'s margins.
        .safeAreaPadding(.horizontal, Spacing.xl)
        .safeAreaPadding(.vertical, Spacing.xxl)
        // Seeded, because `.onMapCameraChange` is not guaranteed to fire on the first settle. The
        // route's rect is narrower than what the padded header shows, so only until the camera says.
        .onAppear { placeArrows(cameraBounds ?? RoutesMapCamera.bounds(for: MKCoordinateRegion(framing))) }
    }

    private func placeArrows(_ visibleBounds: RouteBounds?) {
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

#Preview("Route Detail — dark") {
    let route = RouteSummary.previewRoutes[1]
    routeDetailPreview(route, persistenceClient: .mock(
        routes: RouteSummary.previewRoutes,
        routeDetails: RouteDetail.previewRouteDetails,
        ridesByRoute: [route.id: RouteRideSummary.previewRides]
    ))
    .preferredColorScheme(.dark)
}
