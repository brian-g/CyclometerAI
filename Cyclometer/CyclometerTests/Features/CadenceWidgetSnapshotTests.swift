import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

final class CadenceWidgetSnapshotTests: XCTestCase {

    // W5 grid slots: 2×1 = full row (393×96), 1×1 = half row (196×96).
    private let canvas2x1: SwiftUISnapshotLayout = .fixed(width: 393, height: 96)
    private let canvas1x1: SwiftUISnapshotLayout = .fixed(width: 196, height: 96)

    // Representative cadence history (rpm) sweeping through every zone band.
    private let sampleHistory: [Double] = stride(from: 60.0, to: 105.0, by: 2.25).map { $0 }

    private func widget(
        cadence: Int? = 92,
        history: [Double],
        average: Int = 88,
        max: Int = 104,
        size: WidgetSize,
        scheme: ColorScheme = .light
    ) -> some View {
        let (w, h): (CGFloat, CGFloat) = size == .twoByOne ? (393, 96) : (196, 96)
        return CadenceWidget(
            cadence: cadence,
            cadenceHistory: history,
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

    // MARK: - 1×1

    func testOneByOneActive() {
        assertSnapshot(
            of: widget(history: [], size: .oneByOne),
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
}
