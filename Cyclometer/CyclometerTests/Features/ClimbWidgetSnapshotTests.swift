import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

/// #463 — W22 Climb: on a climb and between climbs in metric and imperial, and with none ahead,
/// each light and dark.
final class ClimbWidgetSnapshotTests: XCTestCase {

    // Grid slot a 2×1 receives: full width, single row.
    private let canvas: SwiftUISnapshotLayout = .fixed(width: 393, height: 96)

    private let climbing = ClimbReading.climbing(.sample, metersToTop: 1_200, metersToClimb: 84, fraction: 0.43)
    private let next = ClimbReading.next(.sample, metersToStart: 3_400)

    private func assertClimb(_ reading: ClimbReading, unit: UnitSystem, dark: Bool = false,
                             file: StaticString = #filePath, testName: String = #function, line: UInt = #line) {
        assertSnapshot(
            of: ClimbWidget(reading: reading, unit: unit)
                .frame(width: 393, height: 96)
                .preferredColorScheme(dark ? .dark : .light),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: dark ? .dark : .light)),
            file: file, testName: testName, line: line
        )
    }

    func testClimbOnAClimbMetric() { assertClimb(climbing, unit: .metric) }
    func testClimbOnAClimbImperial() { assertClimb(climbing, unit: .imperial) }
    func testClimbOnAClimbMetricDark() { assertClimb(climbing, unit: .metric, dark: true) }
    func testClimbOnAClimbImperialDark() { assertClimb(climbing, unit: .imperial, dark: true) }

    func testClimbBetweenClimbsMetric() { assertClimb(next, unit: .metric) }
    func testClimbBetweenClimbsImperial() { assertClimb(next, unit: .imperial) }
    func testClimbBetweenClimbsMetricDark() { assertClimb(next, unit: .metric, dark: true) }
    func testClimbBetweenClimbsImperialDark() { assertClimb(next, unit: .imperial, dark: true) }

    /// No climbs ahead, no route, no elevation and turn-by-turn off all read the same "—".
    func testClimbNoneAhead() { assertClimb(.noClimbAhead, unit: .metric) }
    func testClimbNoneAheadDark() { assertClimb(.noClimbAhead, unit: .metric, dark: true) }
}
