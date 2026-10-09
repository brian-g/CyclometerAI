import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

/// W4 Heart Rate (#145), built as W5 Cadence: the watermark on zone bands, the ▲ trend from
/// Design.sketch "W4 - Heart Rate", and Avg/Max at 2×1.
final class HeartRateWidgetSnapshotTests: XCTestCase {

    // W4 grid slots: 2×1 = full row (393×96), 1×1 = half row (196×96).
    private let canvas2x1: SwiftUISnapshotLayout = .fixed(width: 393, height: 96)
    private let canvas1x1: SwiftUISnapshotLayout = .fixed(width: 196, height: 96)

    /// Rolling between Z1 and Z4 of the default profile.
    private let sampleHistory: [Double] = (0..<60).map { 145 + 22 * sin(Double($0) / 7) }

    private func widget(
        bpm: Int = 156,
        source: HRSource = .bleStrap,
        history: [Double]? = nil,
        trend: HeartRateTrend = .up,
        size: WidgetSize,
        scheme: ColorScheme = .light
    ) -> some View {
        let width: CGFloat = size == .twoByOne ? 393 : 196
        return HeartRateWidget(
            bpm: bpm,
            zone: bpm > 0 ? RiderProfile().zone(forBPM: bpm).rawValue : 0,
            source: source,
            history: history ?? sampleHistory,
            trend: trend,
            averageBPM: bpm > 0 ? 148 : 0,
            maxBPM: bpm > 0 ? 171 : 0,
            size: size
        )
        .frame(width: width, height: 96)
        .preferredColorScheme(scheme)
    }

    // Named for this widget — reference PNGs are flat in the test bundle.

    func testHeartRateWidgetOneByOne() {
        assertSnapshot(of: widget(size: .oneByOne), as: .image(layout: canvas1x1))
    }

    func testHeartRateWidgetOneByOneFallingDark() {
        assertSnapshot(
            of: widget(bpm: 170, trend: .down, size: .oneByOne, scheme: .dark),
            as: .image(layout: canvas1x1, traits: .init(userInterfaceStyle: .dark))
        )
    }

    func testHeartRateWidgetTwoByOne() {
        assertSnapshot(of: widget(size: .twoByOne), as: .image(layout: canvas2x1))
    }

    func testHeartRateWidgetTwoByOneDark() {
        assertSnapshot(
            of: widget(size: .twoByOne, scheme: .dark),
            as: .image(layout: canvas2x1, traits: .init(userInterfaceStyle: .dark))
        )
    }

    func testHeartRateWidgetNoReading() {
        assertSnapshot(of: widget(bpm: 0, history: [], trend: .steady, size: .twoByOne), as: .image(layout: canvas2x1))
    }

    func testHeartRateWidgetNoSource() {
        assertSnapshot(
            of: widget(bpm: 0, source: .none, history: [], trend: .steady, size: .oneByOne),
            as: .image(layout: canvas1x1)
        )
    }
}
