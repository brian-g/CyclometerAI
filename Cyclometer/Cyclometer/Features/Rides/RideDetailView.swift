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
    private var mapHeight: CGFloat { (screenHeight * RideDetailHeaderChrome.mapHeightFraction).rounded() }
    /// A ride S10 never named — recorded before #249, or closed out at launch — has a "" `title`.
    /// `RideRow`'s fallback.
    private var title: String { store.summary.title.isEmpty ? "Ride" : store.summary.title }

    var body: some View {
        List {
            Section {
                if hasHeader {
                    // Clear, so the map behind shows through. The title block starts where the
                    // map starts to fade (UX.md §S15).
                    Button { store.send(.mapTapped) } label: {
                        Color.clear
                            .frame(height: mapHeight - Spacing.mapHeaderFade)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!drawsMap)
                    .accessibilityHidden(!drawsMap)
                    .accessibilityLabel("Route map")
                    .accessibilityHint("Opens the map full screen")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                // The answer, not the frame, so the action runs only when it flips.
                RideTitleBlock(store: store, title: title)
                    .onGeometryChange(for: Bool.self) { [toolbarBottom] proxy in
                        RideDetailHeaderChrome.isTitleUnderToolbar(
                            titleBottom: proxy.frame(in: .global).maxY, toolbarBottom: toolbarBottom
                        )
                    } action: { isTitleUnderToolbar = $0 }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            RideSummarySection(store: store)
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
            // Absent with no radar paired, where "0 passes" would be a claim nobody measured.
            if let passes = store.stats?.vehiclePassCount {
                Section {
                    Button { store.send(.passesTapped) } label: {
                        LabeledContent("Vehicle Passes", value: passes.formatted())
                    }
                    .tint(Color.cyTextPrimary)
                    .disabled(store.vehiclePasses.isEmpty)
                }
            }
        }
        .listSectionSpacing(.compact)
        // The list draws over the map, so its own background is the map's surround instead.
        .scrollContentBackground(.hidden)
        .contentMargins(.top, hasHeader ? 0 : nil, for: .scrollContent)
        .modifier(RideMapHeaderBackground(hasHeader: hasHeader, drawsMap: drawsMap, height: mapHeight,
                                          toolbarBottom: toolbarBottom, header: mapHeader))
        // The title the next screen's back button carries. The bar shows `principal` instead.
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar {
            // In once the title block's name has scrolled under the bar: a fade and a short rise,
            // as S14's inline title comes in when its large title scrolls away. Always laid out,
            // so the bar never resizes the item — inserting it revealed it from the centre.
            ToolbarItem(placement: .principal) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .opacity(isTitleUnderToolbar ? 1 : 0)
                    .offset(y: isTitleUnderToolbar ? 0 : Spacing.sm)
                    .animation(.smooth(duration: 0.25), value: isTitleUnderToolbar)
                    .accessibilityHidden(!isTitleUnderToolbar)
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
                Button("Edit") { store.send(.editTapped) }
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

/// The map behind the list, and the scroll that moves it (#538). A modifier holding the offset as
/// its own state, so a scroll frame re-runs this body alone: the list is its `content`, which a
/// change here doesn't rebuild. View state, not store state: it changes every frame of a scroll
/// and only the chrome reads it.
private struct RideMapHeaderBackground<Header: View>: ViewModifier {
    /// The list runs under the top safe area, with room kept for the header.
    let hasHeader: Bool
    /// The track has loaded, so the map draws in that room.
    let drawsMap: Bool
    let height: CGFloat
    let toolbarBottom: CGFloat
    let header: Header

    /// How far the list has scrolled (`RideDetailHeaderChrome`).
    @State private var scrollOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background(alignment: .top) {
                ZStack(alignment: .top) {
                    Color(.systemGroupedBackground)
                    if drawsMap {
                        RideMapHeaderFrame(height: height, toolbarBottom: toolbarBottom, offset: scrollOffset,
                                           content: header)
                            .transition(.opacity)
                    }
                }
                // In with the track rather than popping in over the room kept for it.
                .animation(.easeIn(duration: 0.25), value: drawsMap)
                .ignoresSafeArea()
            }
            // Under the top safe area only with a map to run under it. Without one, the title
            // block is the first thing below the toolbar.
            .ignoresSafeArea(edges: hasHeader ? .top : [])
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
                scrollOffset = offset
            }
    }
}

/// The map header's frame (#538): pinned to the top of the screen, `height` tall, its bottom
/// `Spacing.mapHeaderFade` fading to the page. It rides up with the list and fades as it goes,
/// and stretches from the top when the rider pulls down past it.
private struct RideMapHeaderFrame<Content: View>: View {
    let height: CGFloat
    let toolbarBottom: CGFloat
    let offset: CGFloat
    let content: Content

    var body: some View {
        content
            // The route fits between the toolbar and the start of the title area (UX.md §S15).
            .safeAreaPadding(.top, toolbarBottom)
            .safeAreaPadding(.bottom, Spacing.mapHeaderFade)
            .frame(height: height)
            .mask {
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: Spacing.mapHeaderFade)
                }
            }
            .scaleEffect(RideDetailHeaderChrome.mapStretch(offset: offset, mapHeight: height), anchor: .top)
            .offset(y: -max(offset, 0))
            .opacity(RideDetailHeaderChrome.mapOpacity(offset: offset, mapHeight: height, fade: Spacing.mapHeaderFade))
            // The clear row in the list above it takes the taps.
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

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

// MARK: - Summary

/// S15's Summary (UX.md §S15): the whole ride at a glance in hero numbers, each left out when the
/// ride recorded nothing for it (#460). Average Power waits for Phase 3.
private struct RideSummarySection: View {
    let store: StoreOf<RideDetailFeature>

    var body: some View {
        if let stats = store.stats {
            let unit = store.unitSystem
            let readings: [(label: String, reading: MetricReading)] = [
                stats.ascent(unit).map { ("Ascent", $0) },
                stats.descent(unit).map { ("Descent", $0) },
                stats.averageSpeed(unit).map { ("Avg Speed", $0) },
                stats.averageHeartRate.map { ("Avg Heart Rate", $0) },
                stats.averageCadence.map { ("Avg Cadence", $0) },
                stats.calories.map { ("Calories", $0) },
            ].compactMap { $0 }
            if !readings.isEmpty {
                Section("Summary") {
                    ReadingColumns {
                        ForEach(readings, id: \.label) { item in
                            ReadingColumn(item.label, item.reading)
                        }
                    }
                }
            }
        }
    }
}

/// S15's Summary values, each nil when the ride recorded nothing for it, so it is left out rather
/// than dashed (UX.md §S15, #460).
extension RideStats {
    func ascent(_ unit: UnitSystem) -> MetricReading? {
        ascentMeters.map { Self.elevation($0, unit) }
    }

    func descent(_ unit: UnitSystem) -> MetricReading? {
        descentMeters.map { Self.elevation($0, unit) }
    }

    /// Nil with no moving second, when the stored average is a 0 nobody rode — the Speed
    /// section's rule (`RideMetrics.hasSpeed`).
    func averageSpeed(_ unit: UnitSystem) -> MetricReading? {
        guard movingSeconds > 0 else { return nil }
        return MetricReading(value: unit.speed(fromMPS: averageSpeedMPS).formatted(.number.precision(.fractionLength(1))),
                             unit: unit.speedLabel, spoken: unit.spokenSpeed(fromMPS: averageSpeedMPS))
    }

    var averageHeartRate: MetricReading? { averageHeartRateBPM.map(Self.heartRate) }

    /// Nil with no cadence sensor. A real 0 rpm average is a reading.
    var averageCadence: MetricReading? {
        averageCadenceRPM.map { MetricReading(value: $0.formatted(), unit: "rpm", spoken: "\($0) rpm") }
    }

    var calories: MetricReading? {
        activeKilocalories.map {
            MetricReading(value: CaloriesMetrics.whole($0), unit: "kcal", spoken: CaloriesMetrics.spoken($0))
        }
    }

    private static func elevation(_ meters: Double, _ unit: UnitSystem) -> MetricReading {
        MetricReading(value: unit.elevation(fromMeters: meters).formatted(.number.precision(.fractionLength(0))),
                      unit: unit.elevationLabel, spoken: unit.spokenElevation(fromMeters: meters))
    }

    private static func heartRate(_ bpm: Int) -> MetricReading {
        MetricReading(value: bpm.formatted(), unit: "bpm", spoken: "\(bpm) beats per minute")
    }
}

// MARK: - Metric sections

/// The dashboard's metric sheets over the whole ride (#536), in UX.md §S15's order: Speed, Pace,
/// Time, Active Calories, Cadence, Cadence Zones, Heart Rate, Heart Rate Zones, Elevation,
/// Climbing, Grade. The sheets' own sections, without their current readings; each is left out
/// when the ride recorded nothing for it.
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
            Section("Elevation") { ElevationReadings(metrics: metrics, showsCurrent: false) }
            ElevationClimbingSection(metrics: metrics)
            ElevationGradeSection(metrics: metrics, showsCurrent: false)
        }
    }
}

// MARK: - Map

/// The recorded track, one polyline per stretch of riding (#263), with start and finish flags.
/// What S15's header and its full-screen map both draw.
struct RideTrackContent: MapContent {
    let segments: [[RouteCoordinate]]

    var body: some MapContent {
        ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
            MapPolyline(coordinates: segment.map(\.coordinate2D))
                .stroke(Color.cyPrimary, lineWidth: Spacing.strokeMapTrack)
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

/// S15's full-screen map (#538): the recorded track, and a marker at each vehicle pass labelled
/// with how fast it went by. Pans and zooms.
struct RideMapView: View {
    let segments: [[RouteCoordinate]]
    let passes: [VehiclePassEventDTO]
    let unitSystem: UnitSystem

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
                RideTrackContent(segments: segments)
                ForEach(Array(passes.enumerated()), id: \.offset) { _, pass in
                    Marker(pass.vehicleSpeed(unitSystem)?.shown ?? "", systemImage: "car.fill",
                           coordinate: CLLocationCoordinate2D(latitude: pass.latitude, longitude: pass.longitude))
                        .tint(passTint(pass.alertLevelAtPass))
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapCompass()
                MapScaleView()
                MapPitchToggle()
            }
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

/// No altitude: no Elevation, Climbing or Grade sections, and no Ascent or Descent (#460).
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
