import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

final class AverageSpeedWidgetSnapshotTests: XCTestCase {

    // Grid slot a 1×1 receives: half-width single row, 196×96.
    private let canvas: SwiftUISnapshotLayout = .fixed(width: 196, height: 96)

    private func makeAverageSpeed(
        averageSpeed: Double = SpeedSample.sampleHourAverage.last!.mps,
        withHistory: Bool = true,
        unit: UnitSystem = .metric,
        scheme: ColorScheme = .light
    ) -> some View {
        AverageSpeedWidget(
            averageSpeed: averageSpeed,
            speedHistory: withHistory ? SpeedSample.sampleHour : [],
            averageHistory: withHistory ? SpeedSample.sampleHourAverage : [],
            unit: unit
        )
        .frame(width: 196, height: 96)
        .preferredColorScheme(scheme)
    }

    func testAverageSpeedMetric() {
        assertSnapshot(of: makeAverageSpeed(unit: .metric), as: .image(layout: canvas))
    }

    func testAverageSpeedImperial() {
        assertSnapshot(of: makeAverageSpeed(unit: .imperial), as: .image(layout: canvas))
    }

    func testAverageSpeedNoMovingTime() {
        assertSnapshot(of: makeAverageSpeed(averageSpeed: 0, withHistory: false), as: .image(layout: canvas))
    }

    func testAverageSpeedMetricDark() {
        assertSnapshot(
            of: makeAverageSpeed(unit: .metric, scheme: .dark),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .dark))
        )
    }
}
