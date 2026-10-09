import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

/// The Ride Metrics sheet's charts and rows (#144), opened from W1/W2/W3/W6/W11. The live ride
/// stops for two minutes, so the pace line breaks and the Time donut has a stopped slice.
///
/// Renders `RideMetricsList` without the sheet's `NavigationStack`: an inline title renders white in
/// an offscreen capture (see `RouteDetailSnapshotTests`), and toolbars don't render at all. What each
/// row reads, and the pace trace's runs, are pinned by `RideMetricsTests`.
final class RideMetricsSheetSnapshotTests: XCTestCase {

    private let canvas: SwiftUISnapshotLayout = .fixed(width: 402, height: 1_160)

    private func makeList(_ metrics: RideMetrics, scheme: ColorScheme) -> some View {
        RideMetricsList(metrics: metrics)
            .frame(width: 402, height: 1_160)
            // The charts label clock times: pinned, or another machine records another image.
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.timeZone, TimeZone(identifier: "America/Chicago")!)
            .preferredColorScheme(scheme)
    }

    // Named for this screen — reference PNGs are flat in the test bundle.

    func testRideMetricsLive() {
        assertSnapshot(
            of: makeList(.sample(), scheme: .light),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .light))
        )
    }

    func testRideMetricsImperialDark() {
        assertSnapshot(
            of: makeList(.sample(.imperial), scheme: .dark),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .dark))
        )
    }

    func testRideMetricsNoData() {
        assertSnapshot(
            of: makeList(RideMetrics(), scheme: .light),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .light))
        )
    }
}
