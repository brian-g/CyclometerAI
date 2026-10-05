import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

final class DurationWidgetSnapshotTests: XCTestCase {

    // Grid slot a 1×1 receives: half-width single row, 196×96.
    private let canvas: SwiftUISnapshotLayout = .fixed(width: 196, height: 96)

    private func makeDuration(elapsed: Int, scheme: ColorScheme = .light) -> some View {
        DurationWidget(elapsed: elapsed)
            .frame(width: 196, height: 96)
            .preferredColorScheme(scheme)
    }

    func testDurationUnderAnHour() {
        assertSnapshot(of: makeDuration(elapsed: 2340), as: .image(layout: canvas))
    }

    func testDurationOverAnHour() {
        assertSnapshot(of: makeDuration(elapsed: 30_873), as: .image(layout: canvas))
    }

    func testDurationRideStart() {
        assertSnapshot(of: makeDuration(elapsed: 0), as: .image(layout: canvas))
    }

    func testDurationOverAnHourDark() {
        assertSnapshot(
            of: makeDuration(elapsed: 30_873, scheme: .dark),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .dark))
        )
    }
}
