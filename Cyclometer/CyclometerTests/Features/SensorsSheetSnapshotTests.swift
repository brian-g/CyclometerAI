import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

/// The ride's Sensors sheet (#466): one row per device, a combo once, its status, and its battery
/// while connected, red at or below 20%.
///
/// Renders `SensorsList` without the sheet's `NavigationStack`, as `CaloriesSheetSnapshotTests` does.
final class SensorsSheetSnapshotTests: XCTestCase {

    private let canvas: SwiftUISnapshotLayout = .fixed(width: 402, height: 360)

    private func assertSheet(
        _ devices: [SensorHealthFeature.Device], scheme: ColorScheme, testName: String = #function
    ) {
        assertSnapshot(
            of: SensorsList(devices: devices)
                .frame(width: 402, height: 360)
                .preferredColorScheme(scheme),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: scheme == .dark ? .dark : .light)),
            testName: testName
        )
    }

    // Named for this screen — reference PNGs are flat in the test bundle.

    func testSensorsSheetMissingAndLow() {
        assertSheet([.sampleRadarLow, .sampleHeartRateHealthy, .sampleComboMissing], scheme: .light)
    }

    func testSensorsSheetMissingAndLowDark() {
        assertSheet([.sampleRadarLow, .sampleHeartRateHealthy, .sampleComboMissing], scheme: .dark)
    }

    func testSensorsSheetTwoMissing() {
        assertSheet([.sampleRadarMissing, .sampleComboMissing], scheme: .light)
    }

    func testSensorsSheetTwoMissingDark() {
        assertSheet([.sampleRadarMissing, .sampleComboMissing], scheme: .dark)
    }
}
