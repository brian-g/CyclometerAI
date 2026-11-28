import ComposableArchitecture
import MapKit
import SwiftUI

/// S15 — Ride Detail, pushed from an S14 row as `RideRoutePath` state (#251), or from S20's
/// Previous Rides on the Routes tab (#426).
///
/// Laid out after Apple Fitness's workout detail (#538): a map header that runs under the top
/// safe area and fades as the list scrolls, the ride's title over the fade, a hero Summary, then
/// the ride's sections. This view owns only the loading, which a snapshot must not run, and the
/// screen's measurements; the screen itself is `RideDetailList`.
struct RideDetailView: View {
    let store: StoreOf<RideDetailFeature>

    var body: some View {
        // The screen's, not the list's: the header is half the screen, and the toolbar's bottom
        // is where the title passes under it.
        GeometryReader { proxy in
            RideDetailList(
                store: store,
                screenHeight: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom,
                toolbarBottom: proxy.safeAreaInsets.top
            )
        }
        .task { await store.send(.task).finish() }
    }
}

/// S15's content, rendered from state alone so a snapshot can seed it.
///
/// Generic over the map header for the reason `RouteDetailList` is: a live `Map` renders its tiles
/// asynchronously and cannot be pixel-snapshotted reproducibly, so tests pass a placeholder.
struct RideDetailList<MapHeader: View>: View {
    @Bindable var store: StoreOf<RideDetailFeature>
    /// The full screen's height, safe areas included. Passed in rather than read from the list,
    /// so a snapshot drawn on a tall canvas still sizes the header to a phone.
    let screenHeight: CGFloat
    /// Where the toolbar ends, from the top of the screen: the map frames the route below it,
    /// and the title moves into it once scrolled above it.
    let toolbarBottom: CGFloat
    let mapHeader: MapHeader

    @State private var isTitleUnderToolbar = false

    init(store: StoreOf<RideDetailFeature>, screenHeight: CGFloat, toolbarBottom: CGFloat,
         @ViewBuilder mapHeader: () -> MapHeader) {
        self.store = store
        self.screenHeight = screenHeight
        self.toolbarBottom = toolbarBottom
        self.mapHeader = mapHeader()
    }

    /// Room for the header, kept while the track loads (`RideDetailFeature.State.reservesMapHeader`).
    private var hasHeader: Bool { store.reservesMapHeader }
    /// The map itself, once there is a track to draw.
    private var drawsMap: Bool { !store.trackSegments.isEmpty }
    private var mapHeight: CGFloat { MapHeaderChrome.mapHeight(screenHeight: screenHeight) }
    /// A ride S10 never named — recorded before #249, or closed out at launch — has a "" `title`.
    /// `RideRow`'s fallback.
    private var title: String { store.summary.title.isEmpty ? "Ride" : store.summary.title }

    var body: some View {
        List {
            Section {
                if hasHeader {
                    MapHeaderTapRow(height: mapHeight, isEnabled: drawsMap) { store.send(.mapTapped) }
                }
                RideTitleBlock(store: store, title: title)
                    .tracksTitleUnderToolbar(toolbarBottom, isUnder: $isTitleUnderToolbar)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            RideSummarySection(stats: store.stats, unit: store.unitSystem) { passes in
                // A `Button`, not a `NavigationLink`, as it opens a sheet, so the chevron saying
                // the row opens something is added here (#660), drawn as a link's: at the trailing
                // edge, beside the label and value when large type stacks them, and greyed with
                // the row while it's disabled, as a disabled link is. A foreground style rather
                // than a tint, which a disabled row doesn't grey; the value keeps its secondary.
                // `_DisclosureIndicator` is the system's own, so it follows Increase Contrast. It
                // is underscored; if an SDK drops it, a hand-drawn `chevron.forward` would need
                // matching to the Route row's again, as no fallback has been checked.
                Button { store.send(.passesTapped) } label: {
                    HStack {
                        LabeledContent {
                            Text(passes.formatted()).foregroundStyle(.secondary)
                        } label: {
                            Text("Vehicle Passes")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        _DisclosureIndicator()
                            .accessibilityHidden(true)
                    }
                }
                .foregroundStyle(Color.cyTextPrimary)
                .disabled(store.vehiclePasses.isEmpty)
            }
            // Under the Summary card, as Design.sketch draws it (#632).
            if let syncedTo = store.syncedTo {
                SyncedToSection(syncedTo: syncedTo) { store.send(.syncedToTapped($0)) } retry: { store.send(.syncRetryTapped) }
            }
            RideDetailMetricSections(store: store)
            // Gone for a free ride. A deleted route keeps its name, without a link (#426).
            if let route = store.route {
                Section("Route") {
                    NavigationLink(state: RideRoutePath.State.route(RouteDetailFeature.State(summary: route))) {
                        Text(route.name)
                    }
                }
            } else if let routeName = store.stats?.routeName {
                Section("Route") {
                    Text(routeName)
                }
            }
            // Strava segments need Accounts, Phase 2 — S20's placeholder idiom.
            Section("Strava Segments") {
                LabeledContent("Connect Strava") {
                    Text("Coming Soon").foregroundStyle(Color.cyTextSecondary)
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
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                MapHeaderToolbarTitle(title: title, isShown: isTitleUnderToolbar)
            }
            // Absent when the finish's GPX export failed, or the rider deleted the file.
            if let url = store.stats?.gpxFileURL {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: url) {
                        Label("Share GPX", systemImage: "square.and.arrow.up")
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                // Off until the stats bring the stored notes (`RideDetailFeature.editTapped`).
                Button("Edit", systemImage: "pencil") { store.send(.editTapped) }
                    .disabled(store.stats == nil)
            }
        }
        .sheet(item: $store.scope(state: \.destination?.mapSheet, action: \.destination.mapSheet)) { store in
            RideMapSheet(store: store)
        }
        .sheet(item: $store.scope(state: \.destination?.passes, action: \.destination.passes)) { store in
            RidePassesSheet(store: store)
        }
        .sheet(item: $store.scope(state: \.destination?.edit, action: \.destination.edit)) { store in
            RideEditView(store: store)
        }
    }
}

extension RideDetailList where MapHeader == RideHeaderMap {
    init(store: StoreOf<RideDetailFeature>, screenHeight: CGFloat, toolbarBottom: CGFloat) {
        self.init(store: store, screenHeight: screenHeight, toolbarBottom: toolbarBottom) {
            RideHeaderMap(segments: store.trackSegments)
        }
    }
}

// MARK: - Header

/// The title over the map's fade (UX.md §S15): the ride's name, its date and time range, the
/// rider's notes, then distance and moving time in small heroes.
private struct RideTitleBlock: View {
    let store: StoreOf<RideDetailFeature>
    let title: String

    var body: some View {
        let unit = store.unitSystem
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(.title)
                .accessibilityAddTraits(.isHeader)
            dateText.font(.headline)
            if let notes = store.stats?.notes, !notes.isEmpty {
                Text(notes)
                    .font(.body)
                    .foregroundStyle(Color.cyTextSecondary)
            }
            // Sketch's "S15 - Ride Detail (Alternative)": value and unit, no labels; VoiceOver
            // names them.
            HStack(alignment: .lastTextBaseline, spacing: Spacing.xl) {
                HeroNumber(unit.distance(fromMeters: store.summary.distanceMeters),
                           unit: unit.distanceLabel)
                    .heroNumberSize(.small)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Distance")
                    .accessibilityValue(unit.spokenDistance(fromMeters: store.summary.distanceMeters))
                // Moving time is W3's, from the `Ride` row, so it arrives with the stats.
                if let seconds = store.stats?.movingSeconds {
                    HeroNumber(seconds.formattedElapsed, unit: "")
                        .heroNumberSize(.small)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Moving time")
                        .accessibilityValue(seconds.spokenElapsed)
                }
            }
            .padding(.top, Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The start date and the time range, "September 26, 2026, 1:31 – 1:40 PM"; the start alone
    /// until the stats bring the end.
    private var dateText: Text {
        let start = store.summary.startedAt
        if let end = store.stats?.endedAt, end > start {
            return Text(start..<end, format: .interval.month(.wide).day().year().hour().minute())
        }
        return Text(start, format: .dateTime.month(.wide).day().year().hour().minute())
    }
}

// MARK: - Metric sections

/// The dashboard's metric sheets over the whole ride (#536), in UX.md §S15's order: Speed, Pace,
/// Time, Weather (#151), Active Calories, Cadence, Cadence Zones, Heart Rate, Heart Rate Zones,
/// Elevation (with the sheet's Climbing and Grade, #548). The sheets' own sections, without their current
/// readings; each is left out when the ride recorded nothing for it.
private struct RideDetailMetricSections: View {
    let store: StoreOf<RideDetailFeature>

    var body: some View {
        if let metrics = store.rideMetrics {
            if metrics.hasSpeed {
                RideSpeedSection(metrics: metrics, showsCurrent: false)
                RidePaceSection(metrics: metrics, showsCurrent: false)
            }
            if metrics.rideSeconds > 0 {
                RideTimeSection(metrics: metrics)
            }
        }
        // After Time (#151). Gone for a ride that recorded no weather: one from before #151, or one
        // where every forecast failed.
        if let samples = store.stats?.weather, !samples.isEmpty {
            RideWeatherSection(
                summary: RideWeatherSummary(samples: samples, exposure: store.windExposure),
                attribution: store.weatherAttribution
            )
        }
        if let metrics = store.caloriesMetrics {
            Section {
                CaloriesReadings(metrics: metrics)
            } header: {
                Text("Active Calories")
            } footer: {
                Text(metrics.footer)
            }
        }
        if let cadence = store.cadence {
            let list = CadenceList(averageCadence: cadence.averageCadence, maxCadence: cadence.maxCadence,
                                   zones: cadence.zones, detail: cadence.detail)
            Section("Cadence") { list.readings }
            Section("Cadence Zones") { list.zoneRows }
        }
        if let metrics = store.heartRateMetrics {
            Section("Heart Rate") { HeartRateReadings(metrics: metrics, showsCurrent: false) }
            Section("Heart Rate Zones") { HeartRateZoneRows(metrics: metrics) }
        }
        if let metrics = store.elevationMetrics {
            ElevationRideSection(metrics: metrics)
        }
    }
}

// MARK: - Map

/// The recorded track, one polyline per stretch of riding (#263), with start and finish flags.
/// What S15's header and its full-screen map both draw.
struct RideTrackContent: MapContent {
    let segments: [[RouteCoordinate]]
    /// The map sheet's route coloring (#537). Plain draws `segments` in the brand color.
    var coloring: RouteColoring = .plain
    var coloredRuns: [ColoredRun] = []

    var body: some MapContent {
        if coloring == .plain || coloredRuns.isEmpty {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                MapPolyline(coordinates: segment.map(\.coordinate2D))
                    .stroke(Color.cyPrimary, lineWidth: Spacing.strokeMapTrack)
            }
        } else {
            ForEach(Array(coloredRuns.enumerated()), id: \.offset) { _, run in
                MapPolyline(coordinates: run.coordinates.map(\.coordinate2D))
                    .stroke(coloring.color(band: run.band), lineWidth: Spacing.strokeMapTrack)
            }
        }
        if let start = segments.first?.first {
            Marker("Start", systemImage: "flag.fill", coordinate: start.coordinate2D)
                .tint(Color.cyPrimary)
        }
        // No finish on a loop, which would stack on the start flag and hide it — the rule
        // and threshold `RouteMapContent` uses. Most rides end where they began.
        if let start = segments.first?.first, let finish = segments.last?.last,
           RouteGeometry.distanceMeters([start, finish]) >= RouteMapContent.loopClosureMeters {
            // `RouteMapContent`'s finish flag, for the reason given there.
            Marker("Finish", systemImage: "flag.checkered", coordinate: finish.coordinate2D)
                .tint(Color.cyTextPrimary)
        }
    }
}

/// S15's map header (#538): the route alone, framed whole, with no panning, zooming or pass
/// markers. Tapping it opens `RideMapSheet`, which has all of those.
///
/// Framed tight on the track (`RideMapThumbnail.headerRect`), with its margins in points, so a
/// short loop fills the header as a long ride does. The live maps' degree padding and 1.7 km
/// floor left a loop under a mile a speck.
struct RideHeaderMap: View {
    let segments: [[RouteCoordinate]]

    var body: some View {
        Map(initialPosition: .rect(RideMapThumbnail.headerRect(for: segments)), interactionModes: []) {
            RideTrackContent(segments: segments)
        }
        .mapStyle(.standard(elevation: .realistic))
        // Room for the start and finish flags, whose balloons stand above their points, and for
        // the track's stroke at the sides.
        .safeAreaPadding(.horizontal, Spacing.xl)
        .safeAreaPadding(.vertical, Spacing.xxl)
    }
}

/// S15's full-screen map (#538): the recorded track, pannable and zoomable, on the chosen
/// basemap, with the route colored by a metric and the pass and stop layers that are on (#537).
struct RideMapView: View {
    let segments: [[RouteCoordinate]]
    var coloring: RouteColoring = .plain
    var coloredRuns: [ColoredRun] = []
    /// Already filtered to the layers that are on: empty when a layer is off or the ride has
    /// nothing for it.
    var stops: [RideStop] = []
    var passes: [VehiclePassEventDTO]
    let unitSystem: UnitSystem
    var basemap: MapBasemap = .standard

    var body: some View {
        if segments.isEmpty {
            // No drawable track — a trainer ride, or one still loading. S14's thumbnail
            // placeholder, rather than a map of somewhere the ride never went.
            Color.cyBgTertiary
                .overlay {
                    Image(systemName: "map")
                        .font(.title)
                        .foregroundStyle(Color.cyTextTertiary)
                }
                .accessibilityHidden(true)
        } else {
            // Padded and floored like every other map, not framed tight like the thumbnail
            // (#280): this one is live, and its markers need room at the edges.
            Map(initialPosition: .region(RoutesMapCamera.region(
                fitting: RouteGeometry.boundingBox(segments.flatMap { $0 })
            ))) {
                RideTrackContent(segments: segments, coloring: coloring, coloredRuns: coloredRuns)
                ForEach(Array(stops.enumerated()), id: \.offset) { _, stop in
                    // The title is all VoiceOver has: MapKit content takes no accessibility
                    // modifiers, so it says which kind of pause as well as how long.
                    Marker(stop.title, systemImage: stop.isAuto ? "pause.circle.fill" : "pause.fill",
                           coordinate: stop.coordinate.coordinate2D)
                        .tint(Color.cyTextSecondary)
                }
                ForEach(Array(passes.enumerated()), id: \.offset) { _, pass in
                    Marker(pass.vehicleSpeed(unitSystem)?.shown ?? "Vehicle pass", systemImage: "car.fill",
                           coordinate: CLLocationCoordinate2D(latitude: pass.latitude, longitude: pass.longitude))
                        .tint(passTint(pass.alertLevelAtPass))
                }
            }
            .mapStyle(mapStyle)
            .mapControls {
                MapCompass()
                MapScaleView()
                MapPitchToggle()
            }
        }
    }

    private var mapStyle: MapStyle {
        switch basemap {
        case .standard: .standard(elevation: .realistic)
        case .hybrid: .hybrid(elevation: .realistic)
        }
    }

    /// The alert level the radar had reached as the vehicle went by, in the radar column's
    /// rating colours.
    private func passTint(_ level: AlertLevel) -> Color {
        switch level {
        case .clear:              return .cyRatingGood
        case .advisory, .caution: return .cyRatingOkay
        case .danger:             return .cyRatingBad
        }
    }
}

// MARK: - Previews

/// S15 already pushed on the Rides tab's own stack, as the app hosts it: the Route row is a
/// `NavigationLink(state:)`, which reports "not presentable" in a plain `NavigationStack` (#426).
private func rideDetailPreview(route: RouteSummary?, sensors: RideDetailPreview.Sensors = .all,
                               notes: String = "") -> some View {
    let summary = RideListSummary(id: UUID(), title: "River Loop", startedAt: .now.addingTimeInterval(-86_400),
                                  distanceMeters: 12_600, durationSeconds: TimeInterval(RideDetailPreview.seconds))
    let track = sensors == .noTrack ? [] : RideDetailPreview.trackPoints(rideId: summary.id, sensors: sensors)
    return withDependencies {
        $0.defaultFileStorage = .inMemory
    } operation: {
        var state = RidesFeature.State()
        state.path.append(.ride(RideDetailFeature.State(summary: summary)))
        return RidesNavigationStack(store: Store(initialState: state) {
            RidesFeature()
        } withDependencies: {
            $0.persistenceClient = .mock(
                trackPoints: [summary.id: track],
                rideStats: [summary.id: RideDetailPreview.stats(track: track, sensors: sensors, route: route, notes: notes)],
                vehiclePassEvents: [summary.id: [RideDetailPreview.pass(rideId: summary.id)]],
                rides: [summary],
                routes: route.map { [$0] } ?? [],
                routeDetails: RouteDetail.previewRouteDetails
            )
        })
    }
}

#Preview("Ride Detail") {
    rideDetailPreview(route: nil)
}

/// GPS only: no Cadence or Heart Rate sections, and no heart rate or cadence in the Summary.
#Preview("Ride Detail — GPS only") {
    rideDetailPreview(route: nil, sensors: .gpsOnly)
}

/// No altitude: no Elevation section, and no Ascent or Descent (#460).
#Preview("Ride Detail — no altitude") {
    rideDetailPreview(route: nil, sensors: .noAltitude)
}

/// The rider's notes under the title block (#538).
#Preview("Ride Detail — notes") {
    rideDetailPreview(route: nil, notes: "Headwind all the way out, tailwind home. New tyres feel quick.")
}

/// No drawable track — a trainer ride: no map header, and the title block at the top (#538).
#Preview("Ride Detail — no track") {
    rideDetailPreview(route: nil, sensors: .noTrack)
}

/// Dark, metric.
#Preview("Ride Detail — dark") {
    rideDetailPreview(route: nil)
        .preferredColorScheme(.dark)
}

/// Ridden on "Summit Climb": the Route section links to its S20 (#426).
#Preview("Ride Detail — on a route") {
    rideDetailPreview(route: RouteSummary.previewRoutes[1])
}

/// A short synthetic ride for the preview only — a loop with a climb, and a heart rate and
/// cadence that follow it.
private enum RideDetailPreview {
    enum Sensors { case all, gpsOnly, noAltitude, noTrack }

    static let seconds = 1_800

    static func trackPoints(rideId: UUID, sensors: Sensors) -> [TrackPointDTO] {
        (0..<seconds).map { second in
            let angle = Double(second) / Double(seconds) * 2 * .pi
            let effort = sin(angle / 2)
            let heartRate = sensors == .gpsOnly ? nil : 120 + Int(40 * effort)
            return TrackPointDTO(
                rideId: rideId,
                timestamp: Date(timeIntervalSince1970: 1_750_000_000 + Double(second)),
                latitude: 37.3349 + 0.01 * sin(angle),
                longitude: -122.0090 + 0.01 * cos(angle),
                altitudeMeters: sensors == .noAltitude ? nil : 100 + 60 * effort,
                horizontalAccuracyMeters: 5,
                speedMPS: 7 - 2 * effort,
                speedSource: .gps,
                heartRateBPM: heartRate,
                heartRateSource: heartRate == nil ? .none : .bleHR,
                cadenceRPM: sensors == .gpsOnly ? nil : 92 - Int(20 * effort)
            )
        }
    }

    /// The `Ride` row's numbers for `track`, worked out as the finish would store them.
    static func stats(track: [TrackPointDTO], sensors: Sensors, route: RouteSummary?, notes: String) -> RideStats {
        let finish = RideFinishStats(savedTrack: track, altitudeSource: .barometric,
                                     movingSeconds: TimeInterval(seconds), distanceMeters: 12_600,
                                     rider: RideEnergy.Rider(kilograms: 75, age: 40, sex: .male))
        let hasSensors = sensors != .gpsOnly && sensors != .noTrack
        let cadence = track.compactMap(\.cadenceRPM)
        let heartRate = track.compactMap(\.heartRateBPM)
        return RideStats(
            averageSpeedMPS: 7, maxSpeedMPS: 9.4,
            averageCadenceRPM: hasSensors ? cadence.reduce(0, +) / cadence.count : nil,
            maxCadenceRPM: cadence.max(),
            vehiclePassCount: 1,
            routeId: route?.id, routeName: route?.name,
            averageHeartRateBPM: hasSensors ? heartRate.reduce(0, +) / heartRate.count : nil,
            maxHeartRateBPM: heartRate.max(),
            ascentMeters: finish.ascentMeters,
            descentMeters: finish.descentMeters,
            activeKilocalories: finish.activeKilocalories,
            calorieSeries: finish.calorieSeries,
            movingSeconds: seconds,
            cadenceSecondsByRPM: Dictionary(cadence.map { ($0, 1.0) }, uniquingKeysWith: +),
            cadenceCoastingSeconds: hasSensors ? 140 : 0,
            endedAt: track.last?.timestamp,
            notes: notes
        )
    }

    static func pass(rideId: UUID) -> VehiclePassEventDTO {
        VehiclePassEventDTO(rideId: rideId, timestamp: Date(timeIntervalSince1970: 1_750_000_060),
                            latitude: 37.3349, longitude: -122.0190, alertLevelAtPass: .caution,
                            riderSpeedKph: 25, estimatedPassSpeedKph: 58)
    }
}
