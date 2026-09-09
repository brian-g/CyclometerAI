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
    private func screen(routes: [RouteSummary]) -> some View {
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
        return NavigationStack {
            RoutesView(store: store)
        }
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
}
