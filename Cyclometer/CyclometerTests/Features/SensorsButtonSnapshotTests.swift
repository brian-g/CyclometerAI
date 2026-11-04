import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

/// The ride toolbar's Sensors button (#464, #466) on the dashboard background, by what it counts.
/// With nothing to count the button isn't drawn at all, which `SensorHealthFeatureTests` pins.
final class SensorsButtonSnapshotTests: XCTestCase {

    private let canvas: SwiftUISnapshotLayout = .fixed(width: 120, height: 120)

    private func assertButton(
        _ devices: [SensorHealthFeature.Device], scheme: ColorScheme, testName: String = #function
    ) {
        assertSnapshot(
            of: ZStack {
                Color.cyBgSecondary
                SensorsButton(devices: devices) {}
            }
            .frame(width: 120, height: 120)
            .preferredColorScheme(scheme),
            // Glass composites against a real window; offscreen, the button's disc isn't drawn.
            as: .image(drawHierarchyInKeyWindow: true, layout: canvas,
                       traits: .init(userInterfaceStyle: scheme == .dark ? .dark : .light)),
            testName: testName
        )
    }

    // Named for this screen — reference PNGs are flat in the test bundle.

    func testSensorsButtonOneMissing() { assertButton([.sampleRadarMissing], scheme: .light) }
    func testSensorsButtonTwoMissing() { assertButton([.sampleRadarMissing, .sampleComboMissing], scheme: .light) }
    func testSensorsButtonOneLow() { assertButton([.sampleRadarLow], scheme: .light) }
    func testSensorsButtonTwoLow() { assertButton([.sampleRadarLow, .sampleHeartRateLow], scheme: .light) }
    func testSensorsButtonMissingAndLow() { assertButton([.sampleComboMissing, .sampleHeartRateLow], scheme: .light) }
    func testSensorsButtonOneMissingDark() { assertButton([.sampleRadarMissing], scheme: .dark) }
    func testSensorsButtonTwoMissingDark() { assertButton([.sampleRadarMissing, .sampleComboMissing], scheme: .dark) }
    func testSensorsButtonOneLowDark() { assertButton([.sampleRadarLow], scheme: .dark) }
    func testSensorsButtonTwoLowDark() { assertButton([.sampleRadarLow, .sampleHeartRateLow], scheme: .dark) }
    func testSensorsButtonMissingAndLowDark() { assertButton([.sampleComboMissing, .sampleHeartRateLow], scheme: .dark) }
}
