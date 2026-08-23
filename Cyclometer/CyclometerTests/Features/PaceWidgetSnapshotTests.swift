import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

final class PaceWidgetSnapshotTests: XCTestCase {

    // Grid slot W11 receives in the factory default: half-width single row, 196×96.
    private let canvas: SwiftUISnapshotLayout = .fixed(width: 196, height: 96)

    private func makePace(
        speedMPS: Double = 3.0,   // ≈ 10.8 km/h ≈ 6.7 mph
        unit: UnitSystem = .metric,
        scheme: ColorScheme = .light
    ) -> some View {
        PaceWidget(speedMPS: speedMPS, unit: unit)
            .frame(width: 196, height: 96)
            .preferredColorScheme(scheme)
    }

    func testMetric() {
        assertSnapshot(of: makePace(unit: .metric), as: .image(layout: canvas))
    }

    func testImperial() {
        assertSnapshot(of: makePace(unit: .imperial), as: .image(layout: canvas))
    }

    func testStoppedShowsPlaceholder() {
        assertSnapshot(of: makePace(speedMPS: 0), as: .image(layout: canvas))
    }

    func testMetricDark() {
        assertSnapshot(
            of: makePace(unit: .metric, scheme: .dark),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .dark))
        )
    }
}
