import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

/// #461 — W19 Distance Remaining.
final class DistanceRemainingWidgetSnapshotTests: XCTestCase {

    // Grid slot a 1×1 receives: half-width single row, 196×96.
    private let canvas: SwiftUISnapshotLayout = .fixed(width: 196, height: 96)

    private func makeDistanceRemaining(
        remaining: Double? = 12_400,   // meters
        unit: UnitSystem = .metric,
        scheme: ColorScheme = .light
    ) -> some View {
        DistanceRemainingWidget(remainingMeters: remaining, unit: unit)
            .frame(width: 196, height: 96)
            .preferredColorScheme(scheme)
    }

    func testDistanceRemainingMidRouteMetric() {
        assertSnapshot(of: makeDistanceRemaining(unit: .metric), as: .image(layout: canvas))
    }

    func testDistanceRemainingMidRouteImperial() {
        assertSnapshot(of: makeDistanceRemaining(unit: .imperial), as: .image(layout: canvas))
    }

    func testDistanceRemainingComplete() {
        assertSnapshot(of: makeDistanceRemaining(remaining: 0), as: .image(layout: canvas))
    }

    func testDistanceRemainingNoRoute() {
        assertSnapshot(of: makeDistanceRemaining(remaining: nil), as: .image(layout: canvas))
    }

    func testDistanceRemainingMidRouteDark() {
        assertSnapshot(
            of: makeDistanceRemaining(scheme: .dark),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .dark))
        )
    }

    func testDistanceRemainingNoRouteDark() {
        assertSnapshot(
            of: makeDistanceRemaining(remaining: nil, scheme: .dark),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .dark))
        )
    }
}
