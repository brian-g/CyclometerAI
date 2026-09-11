import XCTest
import SnapshotTesting
import SwiftUI
import ComposableArchitecture
@testable import Cyclometer

/// S19 — Routes, at the width `Design.sketch` draws the frame at.
///
/// The list and the empty state only. The map view is deliberately absent: a live `MapKit`
/// `Map` renders its tiles asynchronously and the first render per process differs from
/// later ones, so a reference recorded from it is not reproducible. Its behaviour is pinned
/// by `RoutesMapCameraTests` and `RoutesFeatureTests` instead.
///
/// Skipped in CI along with the other snapshot suites — the references were recorded
/// against a local simulator (see `.github/workflows/tests.yml`).
final class RoutesSnapshotTests: XCTestCase {

    /// The iPhone 17 Pro — 402x874pt, with the Dynamic Island's 62pt top inset and the home
    /// indicator's 34pt. A device config rather than a bare `.fixed` canvas: a
    /// `NavigationStack` takes its large title's leading margin from the window's layout
    /// margins, and with no window the title renders flush to x=0.
    private let device = ViewImageConfig(
        safeArea: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0),
        size: CGSize(width: 402, height: 874),
        traits: UITraitCollection(traitsFrom: [
            UITraitCollection(horizontalSizeClass: .compact),
            UITraitCollection(verticalSizeClass: .regular),
            UITraitCollection(displayScale: 3)
        ])
    )

    // MARK: Harness

    /// Imperial and a denied location: the units the row formats with have to be pinned to
    /// something, and denying location keeps the reference free of a simulator fix that
    /// would differ between machines.
    private func screen(
        routes: [RouteSummary],
        filter: RouteFilter = RouteFilter(),
        mapFilterBounds: RouteBounds? = nil,
        mapFilteredRouteIDs: Set<UUID>? = nil
    ) -> some View {
        let storage = FileStorage.inMemory
        let store = withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.preferredUnit = .imperial }
            // Seeded into state rather than left to `.task`: a snapshot captures one layout
            // pass and never awaits an effect, so a fetched list would photograph as empty.
            var state = RoutesFeature.State()
            state.routes = routes
            state.filter = filter
            state.mapFilterBounds = mapFilterBounds
            state.mapFilteredRouteIDs = mapFilteredRouteIDs
            // The screen after its first read, which is the state worth pinning — an
            // unseeded `hasLoaded` would photograph the pre-read blank instead.
            state.hasLoaded = true
            return Store(initialState: state) {
                RoutesFeature()
            } withDependencies: {
                $0.persistenceClient = .mock(routes: routes)
                $0.locationClient = .testValue
                $0.permissionsClient = .mock(initial: [.locationWhenInUse: .denied])
                $0.defaultFileStorage = storage
            }
        }
        // The app's own stack rather than a bare `NavigationStack`: a `NavigationLink(state:)` row
        // outside a store-powered stack reports an issue, which XCTest records as a failure (#195).
        return RoutesNavigationStack(store: store)
            // Explicit rather than ambient: a reference recorded against whatever the host
            // bundle resolved would silently encode that instead of the token.
            .tint(Color.cyPrimary)
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
        assertSnapshot(
            of: UIHostingController(rootView: view.preferredColorScheme(.light)),
            as: .image(on: device),
            named: "\(name)-light", file: file, testName: testName, line: line
        )
        assertSnapshot(
            of: UIHostingController(rootView: view.preferredColorScheme(.dark)),
            as: .image(on: device, traits: .init(userInterfaceStyle: .dark)),
            named: "\(name)-dark", file: file, testName: testName, line: line
        )
    }

    // MARK: Tests

    /// Four saved routes, the last of which carries no `<desc>` — its row has to read as
    /// distance alone rather than leaving a dangling separator.
    func testPopulatedList() {
        assertBothSchemes(screen(routes: RouteSummary.previewRoutes), named: "populated")
    }

    /// Nothing imported yet. The `ContentUnavailableView` and its import action are the
    /// whole screen (UX.md §S19).
    func testEmptyState() {
        assertBothSchemes(screen(routes: []), named: "empty")
    }

    // MARK: Filters (#194)
    //
    // The toolbar is not covered by any of these: a `UIHostingController` renders the
    // navigation bar's items as nothing at all here — the existing references above show a
    // title and a list with no Import or Map/List button either — so the filter button and its
    // badge are pinned by `RoutesFeatureTests` and by the running app, not by pixels.

    /// Filtered by the map and by distance at once. The status bar has to say plainly that the
    /// list is short, and the chip has to offer the way out — without them "my route vanished"
    /// and "this is a bug" are the same experience.
    func testFilteredListShowsStatusBarAndChip() {
        let routes = RouteSummary.previewRoutes
        assertBothSchemes(
            screen(
                routes: routes,
                filter: RouteFilter(distanceMeters: 20_000...40_000, maxElevationGainMeters: nil),
                mapFilterBounds: RouteBounds(minLatitude: 37.30, maxLatitude: 37.40,
                                             minLongitude: -122.06, maxLongitude: -121.97),
                mapFilteredRouteIDs: Set(routes.prefix(2).map(\.id))
            ),
            named: "filtered"
        )
    }

    /// Filters that exclude everything. Kept distinct from the "No Routes" state above: a
    /// rider who filtered too hard must not be told their library is empty.
    ///
    /// The emptiness has to come from a filter the reducer could actually produce. An earlier
    /// version of this pinned `mapFilteredRouteIDs: []` alongside `mapFilterBounds: nil`, which
    /// `refreshMapFilter` never emits — and leaned on `maxElevationGainMeters: 0`, which cannot
    /// empty this list at all, because "Coffee Spin" carries no elevation and `RouteFilter`
    /// always keeps those. The reference would have stayed green through a regression in either
    /// rule. 30–32 km falls between every preview route's distance and is inside the derived
    /// domain, so it is reachable from the sliders.
    func testNoMatchingRoutes() {
        assertBothSchemes(
            screen(
                routes: RouteSummary.previewRoutes,
                filter: RouteFilter(distanceMeters: 30_000...32_000, maxElevationGainMeters: nil)
            ),
            named: "no-matches"
        )
    }

    /// The sheet's own body. Snapshotted without its `NavigationStack` wrapper, because a
    /// sheet carrying `.topBarLeading`/`.topBarTrailing` items renders blank inside a
    /// `UIHostingController` (`StartSheetSnapshotTests.swift:6-13`).
    func testFilterSheet() {
        let storage = FileStorage.inMemory
        let store = withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.preferredUnit = .imperial }
            var state = RoutesFeature.State()
            state.routes = RouteSummary.previewRoutes
            state.hasLoaded = true
            state.filter = RouteFilter(distanceMeters: 20_000...40_000, maxElevationGainMeters: 500)
            return Store(initialState: state) { RoutesFeature() } withDependencies: {
                $0.persistenceClient = .mock(routes: RouteSummary.previewRoutes)
                $0.locationClient = .testValue
                $0.permissionsClient = .mock(initial: [.locationWhenInUse: .denied])
                $0.defaultFileStorage = storage
            }
        }
        assertBothSchemes(
            RouteFilterSheetBody(store: store).tint(Color.cyPrimary),
            named: "sheet"
        )
    }
}
