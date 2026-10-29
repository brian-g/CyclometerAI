import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

/// The Calories sheet's chart and rows (#465), opened from W23: no body mass, early in a ride, and
/// a long ride whose model moved to heart rate.
///
/// Renders `CaloriesList` without the sheet's `NavigationStack`, as `ElevationSheetSnapshotTests`
/// does. Skipped on CI with it: both draw a Swift Charts area recorded on a local simulator.
final class CaloriesSheetSnapshotTests: XCTestCase {

    private let canvas: SwiftUISnapshotLayout = .fixed(width: 402, height: 520)

    private func assertSheet(_ metrics: CaloriesMetrics, scheme: ColorScheme, testName: String = #function) {
        assertSnapshot(
            of: CaloriesList(metrics: metrics)
                .frame(width: 402, height: 520)
                .environment(\.locale, Locale(identifier: "en_US"))
                .preferredColorScheme(scheme),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: scheme == .dark ? .dark : .light)),
            testName: testName
        )
    }

    // Named for this screen — reference PNGs are flat in the test bundle.

    func testCaloriesSheetNoBodyMass() { assertSheet(.sampleNoBodyMass, scheme: .light) }
    func testCaloriesSheetEarlyRide() { assertSheet(.sampleEarly, scheme: .light) }
    func testCaloriesSheetLongRide() { assertSheet(.sampleLong, scheme: .light) }
    func testCaloriesSheetNoBodyMassDark() { assertSheet(.sampleNoBodyMass, scheme: .dark) }
    func testCaloriesSheetEarlyRideDark() { assertSheet(.sampleEarly, scheme: .dark) }
    func testCaloriesSheetLongRideDark() { assertSheet(.sampleLong, scheme: .dark) }
}
