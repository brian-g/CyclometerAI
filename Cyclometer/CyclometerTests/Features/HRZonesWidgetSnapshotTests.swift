import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

/// W12 HR Zones (#145): Design.sketch "W12 - Zones" at 1×1 — a donut beside the time in each zone,
/// the current zone bold — and the same with zone names at 2×1.
final class HRZonesWidgetSnapshotTests: XCTestCase {

    private let canvas2x1: SwiftUISnapshotLayout = .fixed(width: 393, height: 96)
    private let canvas1x1: SwiftUISnapshotLayout = .fixed(width: 196, height: 96)

    /// 37 minutes, most of it in Z2/Z3, one past the hour mark in Z2.
    private let sampleSeconds = [312, 3_846, 702, 318, 42]

    private func widget(
        zone: Int = 3,
        source: HRSource = .bleStrap,
        seconds: [Int]? = nil,
        size: WidgetSize,
        scheme: ColorScheme = .light
    ) -> some View {
        HRZonesWidget(zone: zone, source: source, zoneSeconds: seconds ?? sampleSeconds, size: size)
            .frame(width: size == .twoByOne ? 393 : 196, height: 96)
            .preferredColorScheme(scheme)
    }

    // Named for this widget — reference PNGs are flat in the test bundle.

    func testHRZonesWidgetOneByOne() {
        assertSnapshot(of: widget(size: .oneByOne), as: .image(layout: canvas1x1))
    }

    func testHRZonesWidgetOneByOneDark() {
        assertSnapshot(
            of: widget(size: .oneByOne, scheme: .dark),
            as: .image(layout: canvas1x1, traits: .init(userInterfaceStyle: .dark))
        )
    }

    func testHRZonesWidgetTwoByOne() {
        assertSnapshot(of: widget(size: .twoByOne), as: .image(layout: canvas2x1))
    }

    func testHRZonesWidgetNoTimeYet() {
        assertSnapshot(of: widget(zone: 2, seconds: [], size: .oneByOne), as: .image(layout: canvas1x1))
    }

    func testHRZonesWidgetNoSource() {
        assertSnapshot(of: widget(zone: 0, source: .none, seconds: [], size: .oneByOne), as: .image(layout: canvas1x1))
    }
}
