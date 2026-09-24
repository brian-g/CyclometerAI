import XCTest
import SnapshotTesting
import SwiftUI
import ComposableArchitecture
@testable import Cyclometer

/// S10 — Ride Summary (#249), from seeded state.
///
/// Renders `RideSummaryList` with a placeholder map row, for `RideDetailSnapshotTests`' reasons:
/// no read starts mid-capture, and a live `Map`'s tiles can't be pinned reproducibly. The
/// numbers behind the screen are pinned by `RideSummaryFeatureTests`.
///
/// Skipped in CI along with the other snapshot suites (see `.github/workflows/tests.yml`).
final class RideSummarySnapshotTests: XCTestCase {

    /// `RideDetailSnapshotTests`' device, tall enough for every section.
    private let device = ViewImageConfig(
        safeArea: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0),
        size: CGSize(width: 402, height: 1_500),
        traits: UITraitCollection(traitsFrom: [
            UITraitCollection(horizontalSizeClass: .compact),
            UITraitCollection(verticalSizeClass: .regular),
            UITraitCollection(displayScale: 3)
        ])
    )

    private static let summary = RideListSummary(
        id: UUID(), title: "", startedAt: Date(timeIntervalSince1970: 1_700_035_200),
        distanceMeters: 52_000, durationSeconds: 7_265
    )

    // MARK: Harness

    /// Imperial units, and the state `.task` would have produced seeded directly.
    private func screen(heartRate: Bool, stats: RideStats) -> some View {
        let storage = FileStorage.inMemory
        let store = withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.preferredUnit = .imperial }
            let points = RideSummaryFeatureTests.track(count: 600, heartRate: { second in
                heartRate ? 125 + Int(40 * sin(Double(second) / 40)) : nil
            })
            var state = RideSummaryFeature.State(rideId: Self.summary.id)
            state.load = .loaded
            state.summary = Self.summary
            state.stats = stats
            state.trackSegments = RideMapThumbnail.drawableSegments(points)
            state.elevationProfileMeters = RideDetailSeries.elevationProfile(
                points, sampleCount: RideDetailFeature.chartSampleCount
            )
            state.heartRateSecondsByBPM = RideDetailSeries.secondsByBPM(points)
            state.title = "Morning Ride"
            return Store(initialState: state) {
                RideSummaryFeature()
            } withDependencies: {
                $0.defaultFileStorage = storage
            }
        }
        return RideSummaryList(store: store, mapRow: Color.cyBgTertiary)
            .tint(Color.cyPrimary)
            .environment(\.locale, Locale(identifier: "en_US"))
    }

    /// `testName` defaults to the *caller's* `#function`, so references are filed under the
    /// test that asked for them.
    ///
    /// Drawn in the key window, unlike S15's suite: the Finish Ride button's `.glassProminent`
    /// composites against a window, and offscreen it blanked the *whole* capture to white.
    private func assertBothSchemes(
        _ view: some View,
        named name: String,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        assertSnapshot(
            of: UIHostingController(rootView: view.preferredColorScheme(.light)),
            as: .image(on: device, drawHierarchyInKeyWindow: true, traits: .init(userInterfaceStyle: .light)),
            named: "\(name)-light", file: file, testName: testName, line: line
        )
        assertSnapshot(
            of: UIHostingController(rootView: view.preferredColorScheme(.dark)),
            as: .image(on: device, drawHierarchyInKeyWindow: true, traits: .init(userInterfaceStyle: .dark)),
            named: "\(name)-dark", file: file, testName: testName, line: line
        )
    }

    // MARK: Tests
    //
    // Named for this screen — reference PNGs are flat in the test bundle.

    /// HR, cadence, a paired radar and a route: every row and both charts.
    func testRideSummaryAllSensors() {
        assertBothSchemes(screen(heartRate: true, stats: RideStats(
            averageSpeedMPS: 7.2, maxSpeedMPS: 12.4, averageCadenceRPM: 88, maxCadenceRPM: 109,
            vehiclePassCount: 4, routeName: "SW Fargo"
        )), named: "all-sensors")
    }

    /// GPS alone: no cadence or passes rows, and the zones say so rather than drawing an empty pie.
    func testRideSummaryGPSOnly() {
        assertBothSchemes(screen(heartRate: false, stats: RideStats(averageSpeedMPS: 7.2, maxSpeedMPS: 12.4)),
                          named: "gps-only")
    }

    // No snapshot of the wait for the finalize: in the key window its `ProgressView` animates, so
    // no two captures match. `RideSummaryFeatureTests.waitsForFinalize` pins that state.
}
