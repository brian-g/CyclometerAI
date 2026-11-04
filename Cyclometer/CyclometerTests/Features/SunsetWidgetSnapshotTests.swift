import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

/// #462 — W21 Sunset.
final class SunsetWidgetSnapshotTests: XCTestCase {

    // Grid slot a 1×1 receives: half-width single row, 196×96.
    private let canvas: SwiftUISnapshotLayout = .fixed(width: 196, height: 96)

    private func makeSunset(_ countdown: Sunset.Countdown, scheme: ColorScheme = .light) -> some View {
        SunsetWidget(countdown: countdown)
            .frame(width: 196, height: 96)
            .preferredColorScheme(scheme)
    }

    func testSunsetCountdown() {
        assertSnapshot(of: makeSunset(.minutesLeft(72)), as: .image(layout: canvas))
    }

    /// After sunset and no sunset today read the same "—".
    func testSunsetAfterSunset() {
        assertSnapshot(of: makeSunset(.passed), as: .image(layout: canvas))
    }

    func testSunsetNoFix() {
        assertSnapshot(of: makeSunset(.noFix), as: .image(layout: canvas))
    }

    func testSunsetCountdownDark() {
        assertSnapshot(
            of: makeSunset(.minutesLeft(72), scheme: .dark),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .dark))
        )
    }

    func testSunsetAfterSunsetDark() {
        assertSnapshot(
            of: makeSunset(.passed, scheme: .dark),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .dark))
        )
    }

    func testSunsetNoFixDark() {
        assertSnapshot(
            of: makeSunset(.noFix, scheme: .dark),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .dark))
        )
    }
}
