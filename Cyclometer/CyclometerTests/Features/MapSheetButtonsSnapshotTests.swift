import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

/// #199: the map sheet's own controls, on the dashboard background. The map itself is not snapshotted:
/// a live `Map` renders its tiles asynchronously, and the first render in a process differs from later
/// ones (`RoutesMapCamera.swift`).
final class MapSheetButtonsSnapshotTests: XCTestCase {

    private let canvas: SwiftUISnapshotLayout = .fixed(width: 120, height: 120)

    private func onBackground(_ button: some View, scheme: ColorScheme = .light) -> some View {
        ZStack {
            Color.cyBgSecondary
            button
        }
        .frame(width: 120, height: 120)
        .preferredColorScheme(scheme)
    }

    private var dark: UITraitCollection { .init(userInterfaceStyle: .dark) }

    func testHeadingUp() {
        assertSnapshot(of: onBackground(MapOrientationButton(orientation: .headingUp) {}),
                       as: .image(layout: canvas))
    }

    func testHeadingUpDark() {
        assertSnapshot(of: onBackground(MapOrientationButton(orientation: .headingUp) {}, scheme: .dark),
                       as: .image(layout: canvas, traits: dark))
    }

    func testNorthUp() {
        assertSnapshot(of: onBackground(MapOrientationButton(orientation: .northUp) {}),
                       as: .image(layout: canvas))
    }

    func testNorthUpDark() {
        assertSnapshot(of: onBackground(MapOrientationButton(orientation: .northUp) {}, scheme: .dark),
                       as: .image(layout: canvas, traits: dark))
    }

    func testRouteOverview() {
        assertSnapshot(of: onBackground(RouteOverviewButton {}), as: .image(layout: canvas))
    }

    func testRouteOverviewDark() {
        assertSnapshot(of: onBackground(RouteOverviewButton {}, scheme: .dark),
                       as: .image(layout: canvas, traits: dark))
    }
}
