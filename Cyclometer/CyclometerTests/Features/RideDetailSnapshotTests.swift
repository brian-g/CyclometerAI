import XCTest
import SnapshotTesting
import SwiftUI
// For `navigationDestinationType`: see `screen(_:stats:route:)`.
@_spi(Internals) import ComposableArchitecture
@testable import Cyclometer

/// S15 — Ride Detail (#251, laid out by #538), from seeded state.
///
/// Renders `RideDetailList` with a placeholder map header, for the reasons
/// `RouteDetailSnapshotTests` gives: no read starts mid-capture, and a live `Map`'s tiles cannot
/// be pinned reproducibly. The series behind the charts are pinned by `RideDetailFeatureTests`.
///
/// Skipped in CI along with the other snapshot suites (see `.github/workflows/tests.yml`).
final class RideDetailSnapshotTests: XCTestCase {

    /// `RouteDetailSnapshotTests`' device, drawn tall enough for every section. The header is
    /// sized from `screenHeight`, a phone's, not from this canvas.
    private let device = ViewImageConfig(
        safeArea: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0),
        size: CGSize(width: 402, height: 4_800),
        traits: UITraitCollection { traits in
            traits.horizontalSizeClass = .compact
            traits.verticalSizeClass = .regular
            traits.displayScale = 3
        }
    )

    private static let summary = RideListSummary(
        id: UUID(), title: "River Loop", startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        distanceMeters: points().reduce(0) { $0 + ($1.speedMPS ?? 0) }, durationSeconds: 1_800
    )

    // MARK: Harness

    /// A 30-minute ride over two stretches, as long as the summary says: speed rolling 4–8 m/s,
    /// HR swinging 85–165 bpm, across zones 1–4 of the default profile, steady cadence, and a
    /// rolling climb, each sensor left out on request.
    private static func points(heartRate: Bool = true, cadence: Bool = true, altitude: Bool = true) -> [TrackPointDTO] {
        RideDetailFeatureTests.track(
            count: 1_800,
            heartRate: { heartRate ? 125 + Int(40 * sin(Double($0) / 200)) : nil },
            cadence: cadence ? 88 : nil,
            altitude: { altitude ? 250 + 30 * sin(Double($0) / 300) : nil },
            speed: { 6 + 2 * sin(Double($0) / 150) }
        )
    }

    /// The `Ride` row as the finish stores it for `points`, with the dashboard's own averages.
    private static func stats(_ points: [TrackPointDTO], route: RouteSummary? = nil,
                              bodyMass: Bool = true, radar: Bool = true, notes: String = "") -> RideStats {
        let finish = RideFinishStats(savedTrack: points, altitudeSource: .barometric,
                                     movingSeconds: summary.durationSeconds, distanceMeters: summary.distanceMeters,
                                     rider: bodyMass ? RideEnergy.Rider(kilograms: 75, age: 40, sex: .male) : nil)
        let cadence = points.compactMap(\.cadenceRPM)
        let heartRate = points.compactMap(\.heartRateBPM)
        let speeds = points.compactMap(\.speedMPS)
        return RideStats(
            averageSpeedMPS: summary.distanceMeters / Double(speeds.count), maxSpeedMPS: speeds.max() ?? 0,
            averageCadenceRPM: cadence.isEmpty ? nil : 88, maxCadenceRPM: cadence.isEmpty ? nil : 109,
            vehiclePassCount: radar ? 4 : nil,
            routeId: route?.id, routeName: route?.name,
            averageHeartRateBPM: heartRate.isEmpty ? nil : heartRate.reduce(0, +) / heartRate.count,
            maxHeartRateBPM: heartRate.max(),
            ascentMeters: finish.ascentMeters, descentMeters: finish.descentMeters,
            activeKilocalories: finish.activeKilocalories, calorieSeries: finish.calorieSeries,
            movingSeconds: speeds.count,
            cadenceSecondsByRPM: cadence.isEmpty ? [:] : [72: 300, 84: 600, 91: 450, 99: 150],
            cadenceCoastingSeconds: cadence.isEmpty ? 0 : 150,
            endedAt: summary.startedAt.addingTimeInterval(2_100),
            notes: notes
        )
    }

    /// Imperial units, and the state `.task` would have produced seeded directly.
    private func screen(_ points: [TrackPointDTO], stats: RideStats, route: RouteSummary? = nil,
                        drawsTrack: Bool = true) -> some View {
        let storage = FileStorage.inMemory
        let store = withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.preferredUnit = .imperial }
            var state = RideDetailFeature.State(summary: Self.summary)
            state.trackSegments = drawsTrack ? RideMapThumbnail.drawableSegments(points) : []
            state.track = RideDetailTrack(points: points, altitudeSource: .barometric)
            state.stats = stats
            state.route = route
            return Store(initialState: state) {
                RideDetailFeature()
            } withDependencies: {
                $0.defaultFileStorage = storage
            }
        }
        // A stack with its bar hidden, so no title — the inline-title artefact
        // `RouteDetailSnapshotTests` describes — yet an undimmed Route link, with the type its
        // store-powered stack would set (#426); that suite explains both.
        return NavigationStack {
            // iPhone 17 Pro's screen and status bar (`device`'s top inset).
            // The placeholder runs under the header's safe-area padding, as the `Map` does: the
            // map uses that padding only to frame the route.
            RideDetailList(store: store, screenHeight: 874, toolbarBottom: 62) {
                Color.cyBgTertiary.ignoresSafeArea()
            }
                .toolbar(.hidden, for: .navigationBar)
        }
            .environment(\.navigationDestinationType, RideRoutePath.State.self)
            .tint(Color.cyPrimary)
            .environment(\.locale, Locale(identifier: "en_US"))
    }

    /// `testName` defaults to the *caller's* `#function`, so references are filed under the
    /// test that asked for them.
    private func assertBothSchemes(
        _ view: some View,
        named name: String,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        assertSnapshot(
            of: UIHostingController(rootView: view.preferredColorScheme(.light)),
            as: .image(on: device, traits: .init(userInterfaceStyle: .light)),
            named: "\(name)-light", file: file, testName: testName, line: line
        )
        assertSnapshot(
            of: UIHostingController(rootView: view.preferredColorScheme(.dark)),
            as: .image(on: device, traits: .init(userInterfaceStyle: .dark)),
            named: "\(name)-dark", file: file, testName: testName, line: line
        )
    }

    // MARK: Tests
    //
    // Named for this screen — reference PNGs are flat in the test bundle.

    /// HR, cadence, altitude, a body mass and a paired radar: every section filled (#536), and
    /// every finish-stats row (#460).
    func testRideDetailAllSensors() {
        let points = Self.points()
        assertBothSchemes(screen(points, stats: Self.stats(points)), named: "all-sensors")
    }

    /// GPS alone, with its altitude: no Cadence or Heart Rate sections, and no cadence, HR, pass or
    /// calorie rows — absent rather than dashed.
    func testRideDetailGPSOnly() {
        let points = Self.points(heartRate: false, cadence: false)
        assertBothSchemes(screen(points, stats: Self.stats(points, bodyMass: false, radar: false)),
                          named: "gps-only")
    }

    /// Sensors but no altitude: no Elevation, Climbing or Grade sections, and no Ascent or
    /// Descent rows (#536).
    func testRideDetailNoAltitude() {
        let points = Self.points(altitude: false)
        assertBothSchemes(screen(points, stats: Self.stats(points)), named: "no-altitude")
    }

    /// Notes under the title block, between the date and the hero numbers (#538).
    func testRideDetailNotes() {
        let points = Self.points()
        assertBothSchemes(screen(points, stats: Self.stats(points, notes: "Headwind on the way out, tailwind home.")),
                          named: "notes")
    }

    /// A trainer ride, with no drawable track: no map header, and the title block first under
    /// the toolbar (#538).
    func testRideDetailNoTrack() {
        let points = Self.points()
        assertBothSchemes(screen(points, stats: Self.stats(points), drawsTrack: false), named: "no-track")
    }

    /// Ridden on a saved route: a Route section under the map, linking to S20 (#426).
    func testRideDetailOnRoute() {
        let route = RouteSummary.previewRoutes[1]
        let points = Self.points()
        assertBothSchemes(screen(points, stats: Self.stats(points, route: route), route: route), named: "on-route")
    }

    /// The route has since been deleted: its name stays, with nothing to open (#426).
    func testRideDetailDeletedRoute() {
        let points = Self.points()
        var stats = Self.stats(points)
        stats.routeId = UUID()
        stats.routeName = "Gone Loop"
        assertBothSchemes(screen(points, stats: stats), named: "deleted-route")
    }
}
