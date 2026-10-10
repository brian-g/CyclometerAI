import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

/// The Elevation sheet's charts and rows (#387), opened from W14–W18: mid-ride on a route, and a
/// ride with no altitude yet.
///
/// Renders `ElevationList` without the sheet's `NavigationStack`, as `RideMetricsSheetSnapshotTests`
/// does and for the same reasons. What each row reads is pinned by `ElevationMetricsTests`.
final class ElevationSheetSnapshotTests: XCTestCase {

    private let canvas: SwiftUISnapshotLayout = .fixed(width: 402, height: 1100)

    private func makeList(_ metrics: ElevationMetrics, scheme: ColorScheme) -> some View {
        ElevationList(metrics: metrics)
            .frame(width: 402, height: 1100)
            // The chart labels clock times: pinned, or another machine records another image.
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.timeZone, TimeZone(identifier: "America/Chicago")!)
            .preferredColorScheme(scheme)
    }

    // Named for this screen — reference PNGs are flat in the test bundle.

    func testElevationSheetOnRoute() {
        assertSnapshot(
            of: makeList(.sample(), scheme: .light),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .light))
        )
    }

    func testElevationSheetOnRouteDark() {
        assertSnapshot(
            of: makeList(.sample(), scheme: .dark),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .dark))
        )
    }

    func testElevationSheetNoReading() {
        assertSnapshot(
            of: makeList(ElevationMetrics(), scheme: .light),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .light))
        )
    }
}
