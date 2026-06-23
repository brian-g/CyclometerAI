import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

final class SpeedWidgetSnapshotTests: XCTestCase {

    // Matches the grid slot W1 receives: unit = gridHeight/7, frame = unit*2.
    // 393×200 approximates a typical iPhone in portrait. Width is exact (393pt
    // logical for iPhone 17 Pro); height is representative of unit*2 (~217pt on
    // a 760pt grid, rounded down to keep the canvas conservative).
    private let canvas: SwiftUISnapshotLayout = .fixed(width: 393, height: 200)

    private func makeWidget() -> some View {
        SpeedWidget(
            speed: 28.4,
            activeSpeedSource: .gps,
            distance: 12.3,
            elapsed: 2340,
            averageSpeed: 28.4,
            maxSpeed: 34.1
        )
        .frame(width: 393, height: 200)
    }

    func testGridConstrainedLayout() {
        assertSnapshot(of: makeWidget(), as: .image(layout: canvas))
    }
}
