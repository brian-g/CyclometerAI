import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

final class AverageSpeedWidgetSnapshotTests: XCTestCase {

    // Grid slot a 1×1 receives: half-width single row, 196×96.
    private let canvas: SwiftUISnapshotLayout = .fixed(width: 196, height: 96)

    /// A ride that builds, then fades: the average climbs, then falls — both line colours.
    private let history: (speed: [SpeedSample], average: [SpeedSample]) = {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let speed = (0..<60).map { i in
            let mps = i < 40 ? 4 + Double(i) * 0.15 : 10 - Double(i - 40) * 0.3
            return SpeedSample(time: start.addingTimeInterval(Double(i) * 60), mps: mps)
        }
        var total = 0.0
        let average = speed.enumerated().map { i, sample in
            total += sample.mps
            return SpeedSample(time: sample.time, mps: total / Double(i + 1))
        }
        return (speed, average)
    }()

    private func makeAverageSpeed(
        averageSpeed: Double = 5.6,   // ≈ 20.2 km/h ≈ 12.5 mph
        withHistory: Bool = true,
        unit: UnitSystem = .metric,
        scheme: ColorScheme = .light
    ) -> some View {
        AverageSpeedWidget(
            averageSpeed: averageSpeed,
            speedHistory: withHistory ? history.speed : [],
            averageHistory: withHistory ? history.average : [],
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
