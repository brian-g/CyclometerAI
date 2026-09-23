import XCTest
import SnapshotTesting
import SwiftUI
import ComposableArchitecture
@testable import Cyclometer

/// S15 — Ride Detail (#251), from seeded state.
///
/// Renders `RideDetailList` with a placeholder map row, for the reasons
/// `RouteDetailSnapshotTests` gives: no read starts mid-capture, and a live `Map`'s tiles cannot
/// be pinned reproducibly. The series behind the charts are pinned by `RideDetailFeatureTests`.
///
/// Skipped in CI along with the other snapshot suites (see `.github/workflows/tests.yml`).
final class RideDetailSnapshotTests: XCTestCase {

    /// `RouteDetailSnapshotTests`' device, drawn tall enough for every section — its height too.
    private let device = ViewImageConfig(
        safeArea: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0),
        size: CGSize(width: 402, height: 1_300),
        traits: UITraitCollection(traitsFrom: [
            UITraitCollection(horizontalSizeClass: .compact),
            UITraitCollection(verticalSizeClass: .regular),
            UITraitCollection(displayScale: 3)
        ])
    )

    private static let summary = RideListSummary(
        id: UUID(), title: "River Loop", startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        distanceMeters: 36_050, durationSeconds: 4_712
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
            let points = RideDetailFeatureTests.track(count: 120, heartRate: { second in
                heartRate ? 125 + Int(40 * sin(Double(second) / 20)) : nil
            })
            var state = RideDetailFeature.State(summary: Self.summary)
            state.trackSegments = RideMapThumbnail.drawableSegments(points)
            state.elevationProfileMeters = RideDetailSeries.elevationProfile(
                points, sampleCount: RideDetailFeature.chartSampleCount
            )
            state.heartRateSamples = RideDetailSeries.heartRate(points, sampleCount: RideDetailFeature.chartSampleCount)
            state.stats = stats
            return Store(initialState: state) {
                RideDetailFeature()
            } withDependencies: {
                $0.defaultFileStorage = storage
            }
        }
        // No `NavigationStack`, so no title — the inline-title artefact `RouteDetailSnapshotTests`
        // describes.
        return RideDetailList(store: store, mapRow: Color.cyBgTertiary)
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

    /// HR, cadence and a paired radar: every section filled. HR swings 85–165 bpm, across
    /// zones 1–4 of the default profile, so the chart shows several bands.
    func testRideDetailAllSensors() {
        assertBothSchemes(screen(heartRate: true, stats: RideStats(
            averageSpeedMPS: 7.6, maxSpeedMPS: 12.4, averageCadenceRPM: 88, maxCadenceRPM: 109, vehiclePassCount: 4
        )), named: "all-sensors")
    }

    /// GPS alone: HR says so rather than charting zeros, cadence reads "—", passes are absent.
    func testRideDetailGPSOnly() {
        assertBothSchemes(screen(heartRate: false, stats: RideStats(averageSpeedMPS: 7.6, maxSpeedMPS: 12.4)),
                          named: "gps-only")
    }
}
