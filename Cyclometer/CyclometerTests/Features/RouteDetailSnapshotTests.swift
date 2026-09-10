import XCTest
import SnapshotTesting
import SwiftUI
import ComposableArchitecture
@testable import Cyclometer

/// S20 — Route Detail (#195), from seeded state.
///
/// Renders `RouteDetailList`, not `RouteDetailView`. The list is everything except the loading and
/// the toolbar, so a capture never starts a read that could land between its light and dark
/// images. It also takes its map row as a parameter: a live `Map` renders its tiles asynchronously
/// and the first render per process differs from later ones (`RoutesSnapshotTests`), so these pass
/// a placeholder of the same height, and the chevron and framing arithmetic is pinned by
/// `RouteDirectionMarkersTests` and `RoutesMapCameraTests` instead. The toolbar's "Use This Route"
/// would render as nothing here anyway; `AppRouteSelectionTests` covers it.
///
/// Skipped in CI along with the other snapshot suites — the references were recorded against a
/// local simulator (see `.github/workflows/tests.yml`).
final class RouteDetailSnapshotTests: XCTestCase {

    /// The iPhone 17 Pro's width, insets and scale, drawn taller than the device so the whole
    /// screen — Previous Rides included — is in one reference rather than cut off at the fold.
    private let device = ViewImageConfig(
        safeArea: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0),
        size: CGSize(width: 402, height: 1_300),
        traits: UITraitCollection(traitsFrom: [
            UITraitCollection(horizontalSizeClass: .compact),
            UITraitCollection(verticalSizeClass: .regular),
            UITraitCollection(displayScale: 3)
        ])
    )

    // MARK: Harness

    /// Imperial units, and the state `.task` would have produced seeded directly — a snapshot
    /// captures one layout pass and never awaits an effect.
    private func screen(_ route: RouteSummary, rides: [RouteRideSummary]) -> some View {
        let storage = FileStorage.inMemory
        let store = withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.preferredUnit = .imperial }
            let coordinates = RouteDetail.previewRouteDetails[route.id]?.coordinates ?? []
            var state = RouteDetailFeature.State(summary: route)
            state.coordinates = coordinates
            state.elevationProfileMeters = RouteGeometry.elevationProfile(
                coordinates, sampleCount: RouteDetailFeature.elevationProfileSampleCount
            )
            state.previousRides = rides
            return Store(initialState: state) {
                RouteDetailFeature()
            } withDependencies: {
                $0.defaultFileStorage = storage
            }
        }
        // No `NavigationStack`, so no title. An inline navigation title renders white in an offscreen
        // `UIHostingController` capture on iOS 26 — a bare `List` with an inline title does it too,
        // while a large title offscreen and an inline title drawn in the key window both render in
        // the label colour — so a reference could only ever pin that artefact, never the screen.
        return RouteDetailList(store: store, mapRow: Color.cyBgTertiary)
            // Explicit rather than ambient: a reference recorded against whatever the host bundle
            // resolved would silently encode that instead of the token.
            .tint(Color.cyPrimary)
            // The first reference in this repo to render a date. Pinned, or a machine in another
            // locale or time zone records a different image.
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.timeZone, TimeZone(identifier: "UTC")!)
    }

    /// `testName` defaults to the *caller's* `#function` — Swift evaluates a magic literal
    /// default at the call site — so references are filed under the test that asked for them
    /// rather than under this helper.
    private func assertBothSchemes(
        _ view: some View,
        named name: String,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        // Light pinned as a trait, as dark is, rather than left to whatever the host resolves.
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

    /// "Summit Climb": elevation on every point, and three previous rides, one of them over an hour.
    func testWithElevationAndPreviousRides() {
        assertBothSchemes(screen(RouteSummary.previewRoutes[1], rides: RouteRideSummary.previewRides),
                          named: "elevation-rides")
    }

    func testWithElevationNeverRidden() {
        assertBothSchemes(screen(RouteSummary.previewRoutes[1], rides: []), named: "elevation-no-rides")
    }

    /// "Coffee Spin": a GPX with no `<ele>`, so the whole elevation section is absent.
    func testWithoutElevationWithPreviousRides() {
        assertBothSchemes(screen(RouteSummary.previewRoutes[3], rides: RouteRideSummary.previewRides),
                          named: "no-elevation-rides")
    }

    func testWithoutElevationNeverRidden() {
        assertBothSchemes(screen(RouteSummary.previewRoutes[3], rides: []), named: "no-elevation-no-rides")
    }
}
