import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

final class SpeedWidgetSnapshotTests: XCTestCase {

    // Matches the grid slot W1 receives: unit = gridHeight/7, frame = unit*2.
    // 393×200 approximates a typical iPhone in portrait. Width is exact (393pt
    // logical for iPhone 17 Pro); height is representative of unit*2 (~217pt on
    // a 760pt grid, rounded down to keep the canvas conservative).
    private let canvas: SwiftUISnapshotLayout = .fixed(width: 393, height: 200)

    private func makeWidget(
        speed: Double = 28.4,
        source: SensorSource = .gps,
        distance: Double = 12.3,
        elapsed: Int = 2340,
        averageSpeed: Double = 28.4,
        maxSpeed: Double = 34.1,
        scheme: ColorScheme = .light
    ) -> some View {
        SpeedWidget(
            speed: speed,
            activeSpeedSource: source,
            distance: distance,
            elapsed: elapsed,
            averageSpeed: averageSpeed,
            maxSpeed: maxSpeed
        )
        .frame(width: 393, height: 200)
        .preferredColorScheme(scheme)
    }

    // MARK: - Source badge variants

    func testGridConstrainedLayout() {
        assertSnapshot(of: makeWidget(), as: .image(layout: canvas))
    }

    func testBLEWheelSource() {
        assertSnapshot(of: makeWidget(source: .bleWheel), as: .image(layout: canvas))
    }

    func testNoSource() {
        assertSnapshot(of: makeWidget(speed: 0, source: .none, averageSpeed: 0, maxSpeed: 0), as: .image(layout: canvas))
    }

    // MARK: - Dark mode

    func testGPSSourceDark() {
        assertSnapshot(
            of: makeWidget(scheme: .dark),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .dark))
        )
    }

    func testNoSourceDark() {
        assertSnapshot(
            of: makeWidget(speed: 0, source: .none, averageSpeed: 0, maxSpeed: 0, scheme: .dark),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .dark))
        )
    }

    // MARK: - Edge cases

    func testHighSpeed() {
        // Triple-digit speed to verify layout doesn't clip the hero number.
        assertSnapshot(of: makeWidget(speed: 102.7, averageSpeed: 88.3, maxSpeed: 102.7), as: .image(layout: canvas))
    }
}
