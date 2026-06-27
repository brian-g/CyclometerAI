import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

final class SpeedWidgetSnapshotTests: XCTestCase {

    // Grid slot W1 receives in the factory default: 393×200pt.
    // Width: exact logical pixels for iPhone 17 Pro.
    // Height: representative of unit*2 on a 760pt grid.
    private let canvas2x2: SwiftUISnapshotLayout = .fixed(width: 393, height: 200)

    // Representative speed history (20 ascending samples in m/s)
    private let sampleHistory: [Double] = stride(from: 4.0, to: 9.5, by: 0.275).map { $0 }

    private func make2x2(
        speed: Double? = 7.89,         // m/s ≈ 28.4 km/h
        source: SensorSource = .gps,
        distance: Double = 12_300,     // meters
        elapsed: Int = 2340,
        averageSpeed: Double = 7.89,   // m/s
        maxSpeed: Double = 9.47,       // m/s ≈ 34.1 km/h
        unit: UnitSystem = .metric,
        scheme: ColorScheme = .light
    ) -> some View {
        SpeedWidget(
            speed: speed,
            speedHistory: sampleHistory,
            activeSpeedSource: source,
            distance: distance,
            elapsed: elapsed,
            averageSpeed: averageSpeed,
            maxSpeed: maxSpeed,
            unit: unit,
            size: .twoByTwo
        )
        .frame(width: 393, height: 200)
        .preferredColorScheme(scheme)
    }

    // MARK: - 2×2 — Source badge variants

    func testTwoByTwoGPSSource() {
        assertSnapshot(of: make2x2(), as: .image(layout: canvas2x2))
    }

    func testTwoByTwoBLEWheelSource() {
        assertSnapshot(of: make2x2(source: .bleWheel), as: .image(layout: canvas2x2))
    }

    func testTwoByTwoNoSignal() {
        assertSnapshot(
            of: make2x2(speed: nil, source: .none, averageSpeed: 0, maxSpeed: 0),
            as: .image(layout: canvas2x2)
        )
    }

    // MARK: - 2×2 — Dark mode

    func testTwoByTwoGPSDark() {
        assertSnapshot(
            of: make2x2(scheme: .dark),
            as: .image(layout: canvas2x2, traits: .init(userInterfaceStyle: .dark))
        )
    }

    func testTwoByTwoNoSignalDark() {
        assertSnapshot(
            of: make2x2(speed: nil, source: .none, averageSpeed: 0, maxSpeed: 0, scheme: .dark),
            as: .image(layout: canvas2x2, traits: .init(userInterfaceStyle: .dark))
        )
    }

    // MARK: - 2×2 — Edge cases

    func testTwoByTwoHighSpeed() {
        // ~100 km/h to verify layout doesn't clip the triple-digit hero number.
        assertSnapshot(
            of: make2x2(speed: 27.78, averageSpeed: 24.53, maxSpeed: 27.78),
            as: .image(layout: canvas2x2)
        )
    }

    func testTwoByTwoImperial() {
        assertSnapshot(
            of: make2x2(unit: .imperial),
            as: .image(layout: canvas2x2)
        )
    }

    // MARK: - 2×1 (single grid row: 393×96)

    func testTwoByOneLayout() {
        let canvas: SwiftUISnapshotLayout = .fixed(width: 393, height: 96)
        let widget = SpeedWidget(
            speed: 7.89,
            speedHistory: sampleHistory,
            activeSpeedSource: .gps,
            distance: 12_300,
            elapsed: 2340,
            averageSpeed: 7.89,
            maxSpeed: 9.47,
            unit: .metric,
            size: .twoByOne
        )
        .frame(width: 393, height: 96)
        assertSnapshot(of: widget, as: .image(layout: canvas))
    }

    // MARK: - 1×1 (half-width single row: 196×96)

    func testOneByOneLayout() {
        let canvas: SwiftUISnapshotLayout = .fixed(width: 196, height: 96)
        let widget = SpeedWidget(
            speed: 7.89,
            speedHistory: [],
            activeSpeedSource: .gps,
            distance: 12_300,
            elapsed: 2340,
            averageSpeed: 7.89,
            maxSpeed: 9.47,
            unit: .metric,
            size: .oneByOne
        )
        .frame(width: 196, height: 96)
        assertSnapshot(of: widget, as: .image(layout: canvas))
    }
}
