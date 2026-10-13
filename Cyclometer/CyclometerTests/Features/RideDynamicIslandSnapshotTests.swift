import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

/// #310 — the ride's Live Activity in the Dynamic Island (S22). The island is always black, so each
/// presentation is drawn on black in the dark scheme, as `RideLiveActivity` sets it.
///
/// Compact is laid out as Sketch's "S22 - Dynamic Island" draws it: a 200×37 capsule, the 26pt status
/// mark leading, speed trailing. The system lays out the real one around the camera; the simulator
/// screenshots in the PR cover that.
final class RideDynamicIslandSnapshotTests: XCTestCase {

    private let compactCanvas: SwiftUISnapshotLayout = .fixed(width: 200, height: Spacing.dynamicIsland)
    // The expanded island is 374pt wide on iPhone 17 Pro (simulator); less `Spacing.lg` margins
    // each side, the row gets 342pt.
    private let expandedCanvas: SwiftUISnapshotLayout = .fixed(width: 342, height: 70)

    private func state(
        status: RideStatus = .riding,
        speedMPS: Double = 5.59,
        distanceMeters: Double = 25_270,
        elapsed: TimeInterval = 5_674,
        routeProgress: Double? = 0.42
    ) -> RideActivityAttributes.ContentState {
        // Sketch's 1:34:34, 15.7 mi and 12.5 mph. A riding timer counts from now, so only paused
        // pins the time.
        let start = status == .paused ? Date.now.addingTimeInterval(-elapsed) : .now
        return .init(status: status, startDate: start, pausedElapsed: status == .paused ? elapsed : nil,
                     speedMPS: speedMPS, distanceMeters: distanceMeters, routeProgress: routeProgress)
    }

    private func compact(
        _ state: RideActivityAttributes.ContentState,
        units: UnitSystem = .metric,
        isStale: Bool = false
    ) -> some View {
        HStack {
            RideIslandStatusMark(state: state)
            Spacer(minLength: 0)
            RideIslandSpeed(state: state, units: units, isStale: isStale)
        }
        .padding(.leading, Spacing.xs)
        .padding(.trailing, Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black, in: .capsule)
        .environment(\.colorScheme, .dark)
    }

    private func minimal(_ state: RideActivityAttributes.ContentState) -> some View {
        RideIslandStatusMark(state: state)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black, in: .circle)
            .environment(\.colorScheme, .dark)
    }

    private func expanded(
        _ state: RideActivityAttributes.ContentState,
        units: UnitSystem = .imperial,
        isStale: Bool = false
    ) -> some View {
        RideLockScreenView(state: state, units: units, isStale: isStale, distanceLayout: .horizontal)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(.black)
            .environment(\.colorScheme, .dark)
    }

    /// Passes the caller's name through: the reference is named after the test, not this helper.
    private func snap(_ view: some View, _ layout: SwiftUISnapshotLayout, testName: String = #function) {
        assertSnapshot(of: view, as: .image(layout: layout, traits: .init(userInterfaceStyle: .dark)),
                       testName: testName)
    }

    // MARK: - Compact: status mark leading, speed trailing

    func testDynamicIslandCompactRoute() {
        snap(compact(state()), compactCanvas)
    }

    func testDynamicIslandCompactNoRouteImperial() {
        snap(compact(state(routeProgress: nil), units: .imperial), compactCanvas)
    }

    func testDynamicIslandCompactPaused() {
        snap(compact(state(status: .paused, speedMPS: 0)), compactCanvas)
    }

    /// Three digits: the widest speed the trailing side has to hold.
    func testDynamicIslandCompactFast() {
        snap(compact(state(speedMPS: 28)), compactCanvas)
    }

    func testDynamicIslandCompactStale() {
        snap(compact(state(), isStale: true), compactCanvas)
    }

    // MARK: - Minimal

    func testDynamicIslandMinimalRoute() {
        snap(minimal(state()), .fixed(width: Spacing.dynamicIsland, height: Spacing.dynamicIsland))
    }

    // MARK: - Expanded: the Lock Screen's row, distance's unit inline while it fits

    func testDynamicIslandExpandedRoute() {
        snap(expanded(state()), expandedCanvas)
    }

    /// 25.3 km at 28.4 km/h is wider than the island inline, so distance's unit drops under it.
    func testDynamicIslandExpandedNoRouteMetric() {
        snap(expanded(state(speedMPS: 7.89, routeProgress: nil), units: .metric), expandedCanvas)
    }

    /// The widest row measured: 4:44:44, 125.3 km, 45.0 km/h. Unit under distance, nothing cut.
    func testDynamicIslandExpandedLongRideMetric() {
        snap(expanded(state(status: .paused, speedMPS: 12.5, distanceMeters: 125_300, elapsed: 17_084),
                      units: .metric), expandedCanvas)
    }

    /// Past 9 h the timer's slot is "44:44:44", and even with the unit under distance the row is
    /// ~13pt over, so speed drops its decimal (asked).
    func testDynamicIslandExpandedNineHoursMetric() {
        snap(expanded(state(status: .paused, speedMPS: 12.5, distanceMeters: 125_300, elapsed: 34_200),
                      units: .metric), expandedCanvas)
    }

    /// A 393pt phone (iPhone 15/16): the island is ~365pt, so the row gets ~333pt.
    func testDynamicIslandExpandedNarrowPhone() {
        snap(expanded(state(status: .paused, speedMPS: 12.5, distanceMeters: 125_300, elapsed: 17_084),
                      units: .metric), .fixed(width: 333, height: 70))
    }

    func testDynamicIslandExpandedPaused() {
        snap(expanded(state(status: .paused, speedMPS: 0)), expandedCanvas)
    }

    func testDynamicIslandExpandedStale() {
        snap(expanded(state(status: .paused), isStale: true), expandedCanvas)
    }
}
