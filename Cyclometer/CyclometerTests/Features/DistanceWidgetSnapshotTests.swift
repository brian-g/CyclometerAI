import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

final class DistanceWidgetSnapshotTests: XCTestCase {

    // Grid slot a 1×1 receives: half-width single row, 196×96.
    private let canvas: SwiftUISnapshotLayout = .fixed(width: 196, height: 96)

    private func makeDistance(
        distance: Double = 12_300,   // meters
        unit: UnitSystem = .metric,
        scheme: ColorScheme = .light
    ) -> some View {
        DistanceWidget(distance: distance, unit: unit)
            .frame(width: 196, height: 96)
            .preferredColorScheme(scheme)
    }

    func testDistanceMetric() {
        assertSnapshot(of: makeDistance(unit: .metric), as: .image(layout: canvas))
    }

    func testDistanceImperial() {
        assertSnapshot(of: makeDistance(unit: .imperial), as: .image(layout: canvas))
    }

    func testDistanceRideStart() {
        assertSnapshot(of: makeDistance(distance: 0), as: .image(layout: canvas))
    }

    func testDistanceMetricDark() {
        assertSnapshot(
            of: makeDistance(unit: .metric, scheme: .dark),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .dark))
        )
    }
}
