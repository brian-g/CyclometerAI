import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

/// The Heart Rate sheet's rows (#145), opened from W4 and W12: a live strap reading in zone 3 with
/// time in every zone, and no HR source at all.
///
/// Renders `HeartRateList` without the sheet's `NavigationStack`, as `RideMetricsSheetSnapshotTests`
/// does and for the same reasons. What each row reads is pinned by `HeartRateMetricsTests`.
final class HeartRateSheetSnapshotTests: XCTestCase {

    private let canvas: SwiftUISnapshotLayout = .fixed(width: 402, height: 720)

    private func makeList(_ metrics: HeartRateMetrics, scheme: ColorScheme) -> some View {
        HeartRateList(metrics: metrics)
            .frame(width: 402, height: 720)
            .preferredColorScheme(scheme)
    }

    // Named for this screen — reference PNGs are flat in the test bundle.

    func testHeartRateSheetLive() {
        assertSnapshot(
            of: makeList(.sample, scheme: .light),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .light))
        )
    }

    func testHeartRateSheetLiveDark() {
        assertSnapshot(
            of: makeList(.sample, scheme: .dark),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .dark))
        )
    }

    func testHeartRateSheetNoSource() {
        assertSnapshot(
            of: makeList(HeartRateMetrics(), scheme: .light),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .light))
        )
    }
}
