import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

final class ActiveRideAccessorySnapshotTests: XCTestCase {

    // Full-width strip above the TabBar; height sized for the 40pt ring + padding.
    private let canvas: SwiftUISnapshotLayout = .fixed(width: 393, height: 120)

    private func strip(
        progress: Double? = nil,
        distanceMeters: Double = 12_300,
        speedMPS: Double = 7.89,          // ≈ 28.4 km/h
        elapsedSeconds: Int = 2340,       // 39:00
        unit: UnitSystem = .metric,
        scheme: ColorScheme = .light,
        isCollapsed: Bool? = nil,
        width: CGFloat = 393
    ) -> some View {
        ActiveRideAccessoryView(
            progress: progress,
            distanceMeters: distanceMeters,
            speedMPS: speedMPS,
            elapsedSeconds: elapsedSeconds,
            unit: unit,
            onOpen: {},
            isCollapsedOverride: isCollapsed
        )
        .padding(.horizontal, 4)
        .frame(width: width, height: 120)
        .tint(.cyPrimary)              // mirrors AppView's global tint on the TabView
        .preferredColorScheme(scheme)
    }

    // MARK: - No route → bicycle glyph (the only state reachable today)

    func testNoRouteMetric() {
        assertSnapshot(of: strip(), as: .image(layout: canvas))
    }

    func testNoRouteImperial() {
        assertSnapshot(of: strip(unit: .imperial), as: .image(layout: canvas))
    }

    func testNoRouteDark() {
        assertSnapshot(
            of: strip(scheme: .dark),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .dark))
        )
    }

    // MARK: - With route → completion ring

    func testWithRouteMetric() {
        assertSnapshot(of: strip(progress: 0.42), as: .image(layout: canvas))
    }

    func testWithRouteDark() {
        assertSnapshot(
            of: strip(progress: 0.42, scheme: .dark),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .dark))
        )
    }

    // MARK: - Collapsed into the TabBar (`.inline`) → speed dropped

    /// The inline slot is narrower than the full-width strip; 300pt approximates it
    /// beside the minimised tab button on iPhone 17 Pro.
    func testCollapsedImperial() {
        assertSnapshot(
            of: strip(unit: .imperial, isCollapsed: true, width: 300),
            as: .image(layout: .fixed(width: 300, height: 120))
        )
    }
}
