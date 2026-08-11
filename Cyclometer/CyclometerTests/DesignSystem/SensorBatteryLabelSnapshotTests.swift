import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

final class SensorBatteryLabelSnapshotTests: XCTestCase {

    private func wrap(_ view: some View, scheme: ColorScheme = .light) -> some View {
        view
            .padding()
            .background(Color(.systemBackground))
            .preferredColorScheme(scheme)
    }

    /// Fixed canvas for the same reason `HeroNumberSnapshotTests` uses one:
    /// `.sizeThatFits` mis-measures bare SwiftUI views here.
    private let canvas: SwiftUISnapshotLayout = .fixed(width: 200, height: 80)

    /// One per glyph band, so a change to the banding shows up as a diff.
    private let levels = [100, 78, 50, 30, 12]

    func testLevelsLight() {
        for level in levels {
            assertSnapshot(
                of: wrap(SensorBatteryLabel(percent: level)),
                as: .image(layout: canvas),
                named: "\(level)"
            )
        }
    }

    func testLevelsDark() {
        for level in levels {
            assertSnapshot(
                of: wrap(SensorBatteryLabel(percent: level), scheme: .dark),
                as: .image(layout: canvas, traits: .init(userInterfaceStyle: .dark)),
                named: "\(level)"
            )
        }
    }

    /// The boundary the warning tint turns on at. 20 is low, 21 is not.
    func testLowThresholdBoundary() {
        assertSnapshot(
            of: wrap(SensorBatteryLabel(percent: 20)),
            as: .image(layout: canvas),
            named: "low"
        )
        assertSnapshot(
            of: wrap(SensorBatteryLabel(percent: 21)),
            as: .image(layout: canvas),
            named: "notLow"
        )
    }
}
