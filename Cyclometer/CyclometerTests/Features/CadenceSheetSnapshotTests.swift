import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

/// The Cadence sheet's chart, readings and zones (#494), opened from W5: a 30-minute ride through
/// the zones, and before any reading.
///
/// Renders `CadenceList` without the sheet's `NavigationStack`, as `RideMetricsSheetSnapshotTests`
/// does. Skipped on CI with it: both draw a Swift Charts area recorded on a local simulator.
final class CadenceSheetSnapshotTests: XCTestCase {

    private let canvas: SwiftUISnapshotLayout = .fixed(width: 402, height: 1_000)

    private func assertSheet(
        averageCadence: Int, maxCadence: Int, detail: CadenceDetail, scheme: ColorScheme,
        testName: String = #function
    ) {
        assertSnapshot(
            of: CadenceList(averageCadence: averageCadence, maxCadence: maxCadence, zones: .default, detail: detail)
                .frame(width: 402, height: 1_000)
                // The chart labels clock times: pinned, or another machine records another image.
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.timeZone, TimeZone(identifier: "America/Chicago")!)
                .preferredColorScheme(scheme),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: scheme == .dark ? .dark : .light)),
            testName: testName
        )
    }

    // Named for this screen — reference PNGs are flat in the test bundle.

    func testCadenceSheetActive() {
        assertSheet(averageCadence: 88, maxCadence: 104, detail: .sample, scheme: .light)
    }

    func testCadenceSheetActiveDark() {
        assertSheet(averageCadence: 88, maxCadence: 104, detail: .sample, scheme: .dark)
    }

    func testCadenceSheetNoData() {
        assertSheet(averageCadence: 0, maxCadence: 0, detail: CadenceDetail(), scheme: .light)
    }
}
