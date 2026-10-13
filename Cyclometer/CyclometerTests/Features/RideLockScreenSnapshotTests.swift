import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

/// #309 — the ride's Live Activity on the Lock Screen (S22). The view is hosted on the card the
/// activity's background tint draws, over a stand-in wallpaper, so translucency shows.
final class RideLockScreenSnapshotTests: XCTestCase {

    // Sketch's card: 378pt wide on a 402pt Lock Screen.
    private let canvas: SwiftUISnapshotLayout = .fixed(width: 378, height: 110)

    /// 1:34:34, past the hour, so the frozen timer's format is pinned.
    private static let pausedElapsed: TimeInterval = 5_674

    private func state(
        status: RideStatus = .riding,
        routeProgress: Double? = 0.42,
        pausedElapsed: TimeInterval = RideLockScreenSnapshotTests.pausedElapsed
    ) -> RideActivityAttributes.ContentState {
        // A riding timer counts from now, so it renders 0:00 at snapshot time.
        let start = status == .paused ? Date.now.addingTimeInterval(-pausedElapsed) : .now
        return .init(status: status, startDate: start,
                     pausedElapsed: status == .paused ? pausedElapsed : nil,
                     speedMPS: 7.89, distanceMeters: 12_300, routeProgress: routeProgress)
    }

    private func card(
        _ state: RideActivityAttributes.ContentState,
        units: UnitSystem = .metric,
        isStale: Bool = false,
        isLuminanceReduced: Bool = false,
        scheme: ColorScheme = .light
    ) -> some View {
        RideLockScreenView(state: state, units: units, isStale: isStale)
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(RideLockScreenView.card(colorScheme: scheme, isLuminanceReduced: isLuminanceReduced))
            .background(Color.blue)
            .environment(\.isLuminanceReduced, isLuminanceReduced)
            .preferredColorScheme(scheme)
    }

    /// Passes the caller's name through: the reference is named after the test, not this helper.
    private func dark(_ view: some View, testName: String = #function) {
        assertSnapshot(of: view, as: .image(layout: canvas, traits: .init(userInterfaceStyle: .dark)),
                       testName: testName)
    }

    // MARK: - Riding

    func testLockScreenRouteLight() {
        assertSnapshot(of: card(state()), as: .image(layout: canvas))
    }

    func testLockScreenRouteDark() {
        dark(card(state(), scheme: .dark))
    }

    func testLockScreenNoRouteImperialLight() {
        assertSnapshot(of: card(state(routeProgress: nil), units: .imperial), as: .image(layout: canvas))
    }

    func testLockScreenNoRouteDark() {
        dark(card(state(routeProgress: nil), scheme: .dark))
    }

    // MARK: - Paused → pause icon, frozen timer

    func testLockScreenPausedLight() {
        assertSnapshot(of: card(state(status: .paused)), as: .image(layout: canvas))
    }

    func testLockScreenPausedDark() {
        dark(card(state(status: .paused), scheme: .dark))
    }

    // MARK: - The timer's slot: D-DIN's digits are proportional, "4" the widest

    /// 4:44:44, the widest one-digit-hour time: fits its slot without truncating.
    func testLockScreenWidestTimer() {
        assertSnapshot(of: card(state(status: .paused, pausedElapsed: 17_084)), as: .image(layout: canvas))
    }

    /// 10:00:00: two-digit hours, a ride longer than one activity.
    func testLockScreenTwoDigitHours() {
        assertSnapshot(of: card(state(status: .paused, pausedElapsed: 36_000)), as: .image(layout: canvas))
    }

    /// 9:30:00 metric on a long ride: the row is wider than the card even with distance's unit
    /// under it, so speed drops its decimal (#310 review).
    func testLockScreenNineHoursMetric() {
        let state = RideActivityAttributes.ContentState(
            status: .paused, startDate: .now.addingTimeInterval(-34_200), pausedElapsed: 34_200,
            speedMPS: 12.5, distanceMeters: 125_300, routeProgress: 0.42)
        assertSnapshot(of: card(state), as: .image(layout: canvas))
    }

    // MARK: - Stale → dimmed values, "Reconnecting…"

    func testLockScreenStaleLight() {
        assertSnapshot(of: card(state(status: .paused), isStale: true), as: .image(layout: canvas))
    }

    func testLockScreenStaleDark() {
        dark(card(state(status: .paused), isStale: true, scheme: .dark))
    }

    // MARK: - Reduced luminance → the dark card and white text, in either appearance

    func testLockScreenReducedLuminanceLight() {
        assertSnapshot(of: card(state(status: .paused), isLuminanceReduced: true), as: .image(layout: canvas))
    }
}
