import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

final class CadenceWidgetSnapshotTests: XCTestCase {

    // W5 grid slots: 2×1 = full row (393×96), 1×1 = half row (196×96).
    private let canvas2x1: SwiftUISnapshotLayout = .fixed(width: 393, height: 96)
    private let canvas1x1: SwiftUISnapshotLayout = .fixed(width: 196, height: 96)

    // Representative cadence history (rpm) sweeping through every zone band.
    private let sampleHistory = stride(from: 60.0, to: 105.0, by: 2.25).map { $0 }.asWatermark

    private func widget(
        cadence: Int? = 92,
        history: [WatermarkPoint],
        window: ClosedRange<Date>? = nil,
        average: Int = 88,
        max: Int = 104,
        size: WidgetSize,
        scheme: ColorScheme = .light
    ) -> some View {
        let (w, h): (CGFloat, CGFloat) = size == .twoByOne ? (393, 96) : (196, 96)
        return CadenceWidget(
            cadence: cadence,
            cadenceHistory: history,
            watermarkWindow: window,
            averageCadence: average,
            maxCadence: max,
            size: size
        )
        .frame(width: w, height: h)
        .preferredColorScheme(scheme)
    }

    // MARK: - 2×1

    func testTwoByOneActive() {
        assertSnapshot(
            of: widget(history: sampleHistory, size: .twoByOne),
            as: .image(layout: canvas2x1)
        )
    }

    func testTwoByOneNoSignal() {
        assertSnapshot(
            of: widget(cadence: nil, history: [], average: 0, max: 0, size: .twoByOne),
            as: .image(layout: canvas2x1)
        )
    }

    func testTwoByOneActiveDark() {
        assertSnapshot(
            of: widget(history: sampleHistory, size: .twoByOne, scheme: .dark),
            as: .image(layout: canvas2x1, traits: .init(userInterfaceStyle: .dark))
        )
    }

    /// The sensor asleep through a stop: the trace breaks for the silence and picks up after it, at
    /// its own place on the shared window rather than closed up against the readings before it.
    func testCadenceTwoByOneSensorGap() {
        let gapped = sampleHistory.enumerated().map { index, point in
            WatermarkPoint(time: point.time, value: point.value, run: index < 8 ? 0 : 1)
        }.filter { !(8..<12).contains(Int($0.time.timeIntervalSinceReferenceDate)) }
        assertSnapshot(
            of: widget(history: gapped, window: sampleHistory.plotDomain(nil), size: .twoByOne),
            as: .image(layout: canvas2x1)
        )
    }

    // MARK: - 1×1

    func testOneByOneActive() {
        assertSnapshot(
            of: widget(history: sampleHistory, size: .oneByOne),
            as: .image(layout: canvas1x1)
        )
    }

    func testOneByOneNoSignal() {
        assertSnapshot(
            of: widget(cadence: nil, history: [], average: 0, max: 0, size: .oneByOne),
            as: .image(layout: canvas1x1)
        )
    }

    func testOneByOneNoSignalDark() {
        assertSnapshot(
            of: widget(cadence: nil, history: [], average: 0, max: 0, size: .oneByOne, scheme: .dark),
            as: .image(layout: canvas1x1, traits: .init(userInterfaceStyle: .dark))
        )
    }

    // MARK: - Trend (#402)

    func testCadenceOneByOneTrendUp() {
        assertSnapshot(
            of: widget(cadence: 96, history: sampleHistory, size: .oneByOne),
            as: .image(layout: canvas1x1)
        )
    }

    func testCadenceTwoByOneTrendDown() {
        // The one size where the ▼ sits between the cadence and AVG.
        assertSnapshot(
            of: widget(cadence: 78, history: sampleHistory, size: .twoByOne),
            as: .image(layout: canvas2x1)
        )
    }

    func testCadenceTrendDownDark() {
        assertSnapshot(
            of: widget(cadence: 78, history: sampleHistory, size: .oneByOne, scheme: .dark),
            as: .image(layout: canvas1x1, traits: .init(userInterfaceStyle: .dark))
        )
    }
}
