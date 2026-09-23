import ComposableArchitecture
import MapKit
import SwiftUI

/// S15 — Ride Detail, pushed from an S14 row as `RidesFeature.Path` state (#251).
///
/// The prototype's layout, now reading the persisted ride. This view owns only the loading,
/// which a snapshot must not run; the screen itself is `RideDetailList`.
struct RideDetailView: View {
    let store: StoreOf<RideDetailFeature>

    /// UX.md §S15: a 240pt map. Kept here because the generic `RideDetailList` cannot hold
    /// static stored properties.
    static let mapHeight: CGFloat = 240
    static let chartHeight: CGFloat = 140

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
            Section("Elevation Profile") {
                if let profile = store.elevationProfileMeters {
                    ElevationProfileView(samples: profile.map(unit.elevation(fromMeters:)),
                                         unitLabel: unit.elevationLabel)
                        .frame(height: RideDetailView.chartHeight)
                        .padding(.vertical, Spacing.sm)
                } else {
                    unavailable("No elevation recorded")
                }
            }
            Section("Stats") {
                LabeledContent("Avg Speed (\(unit.speedLabel))",
                               value: speedText(store.stats?.averageSpeedMPS, unit))
                LabeledContent("Max Speed (\(unit.speedLabel))",
                               value: speedText(store.stats?.maxSpeedMPS, unit))
                // A dash, not 0, for a ride with no cadence sensor — 0 rpm is a real reading.
                LabeledContent("Avg Cadence (rpm)", value: countText(store.stats?.averageCadenceRPM))
                LabeledContent("Max Cadence (rpm)", value: countText(store.stats?.maxCadenceRPM))
                // Absent with no radar paired, where "0 passes" would be a claim nobody measured.
                if let passes = store.stats?.vehiclePassCount {
                    LabeledContent("Vehicle Passes", value: passes.formatted())
                }
            }
            Section("HR Profile") {
                if store.heartRateSamples.isEmpty {
                    unavailable("No heart rate recorded")
                } else {
                    HeartRateProfileView(samples: store.heartRateSamples, zoneBounds: store.heartRateZoneBounds)
                        .frame(height: RideDetailView.chartHeight)
                        .padding(.vertical, Spacing.sm)
                }
            }
            // Strava segments need Accounts, Phase 2 — S20's placeholder idiom.
            Section("Strava Segments") {
                LabeledContent("Connect Strava") { unavailable("Coming Soon") }
            }
        }
        // Every ride's `title` is "" until #249's rename field ships — `RideRow`'s fallback.
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

    private func countText(_ value: Int?) -> String {
        value?.formatted() ?? "—"
    }
}

extension RideDetailList where MapRow == RideMapView {
    init(store: StoreOf<RideDetailFeature>) {
        self.init(store: store, mapRow: RideMapView(segments: store.trackSegments,
                                                    passes: store.vehiclePasses,
                                                    unitSystem: store.unitSystem))
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
            Map(initialPosition: .region(RideMapThumbnail.region(for: segments))) {
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

#Preview("Ride Detail") {
    let summary = RideListSummary(id: UUID(), title: "River Loop", startedAt: .now.addingTimeInterval(-86_400),
                                  distanceMeters: 36_050, durationSeconds: 4_712)
    return withDependencies {
        $0.defaultFileStorage = .inMemory
    } operation: {
        NavigationStack {
            RideDetailView(store: Store(initialState: RideDetailFeature.State(summary: summary)) {
                RideDetailFeature()
            } withDependencies: {
                $0.persistenceClient = .mock(
                    trackPoints: [summary.id: RideDetailPreview.trackPoints(rideId: summary.id)],
                    rideStats: [summary.id: RideStats(averageSpeedMPS: 7.6, maxSpeedMPS: 12.4,
                                                      averageCadenceRPM: 88, maxCadenceRPM: 109,
                                                      vehiclePassCount: 1)],
                    vehiclePassEvents: [summary.id: [RideDetailPreview.pass(rideId: summary.id)]]
                )
            })
        }
    }
}

/// A short synthetic ride for the preview only — a loop with a climb and a heart rate that
/// follows it.
private enum RideDetailPreview {
    static func trackPoints(rideId: UUID) -> [TrackPointDTO] {
        (0..<120).map { second in
            let angle = Double(second) / 120 * 2 * .pi
            return TrackPointDTO(
                rideId: rideId,
                timestamp: Date(timeIntervalSince1970: 1_750_000_000 + Double(second)),
                latitude: 37.3349 + 0.01 * sin(angle),
                longitude: -122.0090 + 0.01 * cos(angle),
                altitudeMeters: 100 + 40 * sin(angle / 2),
                horizontalAccuracyMeters: 5,
                speedMPS: 7,
                speedSource: .gps,
                heartRateBPM: 120 + Int(30 * sin(angle / 2)),
                heartRateSource: .bleHR,
                cadenceRPM: 88
            )
        }
    }

    static func pass(rideId: UUID) -> VehiclePassEventDTO {
        VehiclePassEventDTO(rideId: rideId, timestamp: Date(timeIntervalSince1970: 1_750_000_060),
                            latitude: 37.3349, longitude: -122.0190, alertLevelAtPass: .caution,
                            riderSpeedKph: 25, estimatedPassSpeedKph: 58)
    }
}
