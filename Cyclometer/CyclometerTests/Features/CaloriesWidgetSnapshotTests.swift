import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

/// #465 — W23 Active Calories: no body mass, early in a ride, and a long ride.
final class CaloriesWidgetSnapshotTests: XCTestCase {

    // Grid slot a 1×1 receives: half-width single row, 196×96.
    private let canvas: SwiftUISnapshotLayout = .fixed(width: 196, height: 96)

    private func makeCalories(_ metrics: CaloriesMetrics, scheme: ColorScheme = .light) -> some View {
        CaloriesWidget(kilocalories: metrics.latest?.kilocalories, rider: metrics.rider)
            .frame(width: 196, height: 96)
            .preferredColorScheme(scheme)
    }

    private func assertCalories(_ metrics: CaloriesMetrics, scheme: ColorScheme, testName: String = #function) {
        assertSnapshot(
            of: makeCalories(metrics, scheme: scheme),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: scheme == .dark ? .dark : .light)),
            testName: testName
        )
    }

    func testCaloriesNoBodyMass() { assertCalories(.sampleNoBodyMass, scheme: .light) }
    func testCaloriesEarlyRide() { assertCalories(.sampleEarly, scheme: .light) }
    func testCaloriesLongRide() { assertCalories(.sampleLong, scheme: .light) }
    func testCaloriesNoBodyMassDark() { assertCalories(.sampleNoBodyMass, scheme: .dark) }
    func testCaloriesEarlyRideDark() { assertCalories(.sampleEarly, scheme: .dark) }
    func testCaloriesLongRideDark() { assertCalories(.sampleLong, scheme: .dark) }
}
