import ComposableArchitecture
import MapKit
import SwiftUI

/// S15 — Ride Detail, pushed from an S14 row as `RideRoutePath` state (#251), or from S20's
/// Previous Rides on the Routes tab (#426).
///
/// The prototype's layout, now reading the persisted ride. This view owns only the loading,
/// which a snapshot must not run; the screen itself is `RideDetailList`.
struct RideDetailView: View {
    let store: StoreOf<RideDetailFeature>

    /// UX.md §S15: a 240pt map. Kept here because the generic `RideDetailList` cannot hold
    /// static stored properties.
    static let mapHeight: CGFloat = 240

    var body: some View {
        RideDetailList(store: store)
            .task { await store.send(.task).finish() }
    }
}

/// S15's content, rendered from state alone so a snapshot can seed it.
///
/// Generic over the map row for the reason `RouteDetailList` is: a live `Map` renders its tiles
/// asynchronously and cannot be pixel-snapshotted reproducibly, so tests pass a placeholder of
/// the same height.
struct RideDetailList<MapRow: View>: View {
    let store: StoreOf<RideDetailFeature>
    let mapRow: MapRow

    var body: some View {
        let unit = store.unitSystem
        List {
            Section {
                mapRow
                    .frame(height: RideDetailView.mapHeight)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerMd, style: .continuous))
                    .listRowInsets(EdgeInsets())
            }
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
            Section("Stats") {
                // A row is absent, not dashed, for a ride that recorded nothing for it (UX.md
                // §S15, #460): no altitude, heart rate, cadence sensor or body mass in Health.
                if let reading = store.stats?.ascent(unit) { statRow("Ascent", reading) }
                if let reading = store.stats?.descent(unit) { statRow("Descent", reading) }
                LabeledContent("Avg Speed (\(unit.speedLabel))",
                               value: speedText(store.stats?.averageSpeedMPS, unit))
                LabeledContent("Max Speed (\(unit.speedLabel))",
                               value: speedText(store.stats?.maxSpeedMPS, unit))
                if let reading = store.stats?.averageHeartRate { statRow("Avg Heart Rate", reading) }
                if let reading = store.stats?.maxHeartRate { statRow("Max Heart Rate", reading) }
                // Absent, not 0, for a ride with no cadence sensor — 0 rpm is a real reading.
                if let rpm = store.stats?.averageCadenceRPM {
                    LabeledContent("Avg Cadence (rpm)", value: rpm.formatted())
                }
                if let rpm = store.stats?.maxCadenceRPM {
                    LabeledContent("Max Cadence (rpm)", value: rpm.formatted())
                }
                if let reading = store.stats?.calories { statRow("Calories", reading) }
                // Absent with no radar paired, where "0 passes" would be a claim nobody measured.
                if let passes = store.stats?.vehiclePassCount {
                    LabeledContent("Vehicle Passes", value: passes.formatted())
                }
            }
            RideDetailMetricSections(store: store)
            // Strava segments need Accounts, Phase 2 — S20's placeholder idiom.
            Section("Strava Segments") {
                LabeledContent("Connect Strava") { unavailable("Coming Soon") }
            }
        }
        // A ride S10 never named — recorded before #249, or closed out at launch — has a ""
        // `title`. `RideRow`'s fallback.
        .navigationTitle(store.summary.title.isEmpty ? "Ride" : store.summary.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func unavailable(_ text: String) -> some View {
        Text(text).foregroundStyle(Color.cyTextSecondary)
    }

    private func speedText(_ mps: Double?, _ unit: UnitSystem) -> String {
        guard let mps else { return "—" }
        return unit.speed(fromMPS: mps).formatted(.number.precision(.fractionLength(1)))
    }

    /// A row in the section's "Label (unit)" style, read by VoiceOver as the label and the value
    /// with its unit in words (#460), rather than the symbol in brackets.
    private func statRow(_ title: String, _ reading: MetricReading) -> some View {
        LabeledContent("\(title) (\(reading.unit))", value: reading.value)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(reading.spoken)
    }
}

/// S15's #460 rows, each nil when the ride recorded nothing for it, so the row is left out
/// rather than dashed (UX.md §S15).
extension RideStats {
    func ascent(_ unit: UnitSystem) -> MetricReading? {
        ascentMeters.map { Self.elevation($0, unit) }
    }

    func descent(_ unit: UnitSystem) -> MetricReading? {
        descentMeters.map { Self.elevation($0, unit) }
    }

    var averageHeartRate: MetricReading? { averageHeartRateBPM.map(Self.heartRate) }
    var maxHeartRate: MetricReading? { maxHeartRateBPM.map(Self.heartRate) }

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

extension RideDetailList where MapRow == RideMapView {
    init(store: StoreOf<RideDetailFeature>) {
        self.init(store: store, mapRow: RideMapView(segments: store.trackSegments,
                                                    passes: store.vehiclePasses,
                                                    unitSystem: store.unitSystem))
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

/// S15's map: the recorded track, one polyline per stretch of riding (#263), start and finish
/// flags, and a marker at each vehicle pass labelled with how fast it went by.
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
                ForEach(Array(passes.enumerated()), id: \.offset) { _, pass in
                    Marker(passLabel(pass), systemImage: "car.fill",
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

    /// The vehicle's own speed, in the rider's units, or no label when the radar never
    /// measured one.
    private func passLabel(_ pass: VehiclePassEventDTO) -> String {
        guard let kph = pass.estimatedPassSpeedKph else { return "" }
        let speed = unitSystem.speed(fromMPS: kph / AlertLevel.kphPerMPS)
        return "\(speed.formatted(.number.precision(.fractionLength(0)))) \(unitSystem.speedLabel)"
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
private func rideDetailPreview(route: RouteSummary?, sensors: RideDetailPreview.Sensors = .all) -> some View {
    let summary = RideListSummary(id: UUID(), title: "River Loop", startedAt: .now.addingTimeInterval(-86_400),
                                  distanceMeters: 12_600, durationSeconds: TimeInterval(RideDetailPreview.seconds))
    let track = RideDetailPreview.trackPoints(rideId: summary.id, sensors: sensors)
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
                rideStats: [summary.id: RideDetailPreview.stats(track: track, sensors: sensors, route: route)],
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

/// GPS only: no Cadence or Heart Rate sections, and no HR or cadence rows in Stats.
#Preview("Ride Detail — GPS only") {
    rideDetailPreview(route: nil, sensors: .gpsOnly)
}

/// No altitude: no Elevation, Climbing or Grade sections, and no Ascent or Descent (#460).
#Preview("Ride Detail — no altitude") {
    rideDetailPreview(route: nil, sensors: .noAltitude)
}

/// Ridden on "Summit Climb": the Route section links to its S20 (#426).
#Preview("Ride Detail — on a route") {
    rideDetailPreview(route: RouteSummary.previewRoutes[1])
}

/// A short synthetic ride for the preview only — a loop with a climb, and a heart rate and
/// cadence that follow it.
private enum RideDetailPreview {
    enum Sensors { case all, gpsOnly, noAltitude }

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
    static func stats(track: [TrackPointDTO], sensors: Sensors, route: RouteSummary?) -> RideStats {
        let finish = RideFinishStats(savedTrack: track, altitudeSource: .barometric,
                                     movingSeconds: TimeInterval(seconds), distanceMeters: 12_600,
                                     rider: RideEnergy.Rider(kilograms: 75, age: 40, sex: .male))
        let hasSensors = sensors != .gpsOnly
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
            cadenceCoastingSeconds: hasSensors ? 140 : 0
        )
    }

    static func pass(rideId: UUID) -> VehiclePassEventDTO {
        VehiclePassEventDTO(rideId: rideId, timestamp: Date(timeIntervalSince1970: 1_750_000_060),
                            latitude: 37.3349, longitude: -122.0190, alertLevelAtPass: .caution,
                            riderSpeedKph: 25, estimatedPassSpeedKph: 58)
    }
}
