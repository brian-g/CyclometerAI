import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

/// W9 — Directions (#200), at both of its sizes, with a turn ahead and with no route.
final class DirectionsWidgetSnapshotTests: XCTestCase {

    /// The widget's content — the three things W9 can show.
    private enum Content { case turn, noTurnAhead, noRoute }

    /// A cue with its own words, so the 2×1 instruction text is exercised.
    private let turn = Maneuver(
        coordinate: RouteCoordinate(latitude: 0, longitude: 0, elevationMeters: nil),
        direction: .right,
        name: "Turn right onto County Road S",
        distanceAlongRouteMeters: 1_000
    )

    // W9 grid slots: 2×1 = full row (393×96), 1×1 = half row (196×96).
    private let canvas2x1: SwiftUISnapshotLayout = .fixed(width: 393, height: 96)
    private let canvas1x1: SwiftUISnapshotLayout = .fixed(width: 196, height: 96)

    private func widget(
        _ content: Content,
        size: WidgetSize,
        unit: UnitSystem = .metric,
        scheme: ColorScheme = .light
    ) -> some View {
        let (width, height): (CGFloat, CGFloat) = size == .twoByOne ? (393, 96) : (196, 96)
        return DirectionsWidget(
            hasRoute: content != .noRoute,
            nextTurn: content == .turn ? turn : nil,
            distanceMeters: content == .turn ? 347 : nil,
            unit: unit,
            size: size
        )
        .frame(width: width, height: height)
        .preferredColorScheme(scheme)
    }

    // MARK: - 2×1

    func testTwoByOneTurn() {
        assertSnapshot(of: widget(.turn, size: .twoByOne), as: .image(layout: canvas2x1))
    }

    func testTwoByOneTurnDark() {
        assertSnapshot(
            of: widget(.turn, size: .twoByOne, scheme: .dark),
            as: .image(layout: canvas2x1, traits: .init(userInterfaceStyle: .dark))
        )
    }

    func testTwoByOneNoRoute() {
        assertSnapshot(of: widget(.noRoute, size: .twoByOne), as: .image(layout: canvas2x1))
    }

    func testTwoByOneNoRouteDark() {
        assertSnapshot(
            of: widget(.noRoute, size: .twoByOne, scheme: .dark),
            as: .image(layout: canvas2x1, traits: .init(userInterfaceStyle: .dark))
        )
    }

    // MARK: - 1×1 (the dashboard's slot)

    func testOneByOneTurn() {
        assertSnapshot(of: widget(.turn, size: .oneByOne), as: .image(layout: canvas1x1))
    }

    func testOneByOneTurnDark() {
        assertSnapshot(
            of: widget(.turn, size: .oneByOne, scheme: .dark),
            as: .image(layout: canvas1x1, traits: .init(userInterfaceStyle: .dark))
        )
    }

    func testOneByOneNoRoute() {
        assertSnapshot(of: widget(.noRoute, size: .oneByOne), as: .image(layout: canvas1x1))
    }

    func testOneByOneNoRouteDark() {
        assertSnapshot(
            of: widget(.noRoute, size: .oneByOne, scheme: .dark),
            as: .image(layout: canvas1x1, traits: .init(userInterfaceStyle: .dark))
        )
    }

    /// Route loaded, but no distance: before the first match, off route, past the last turn.
    func testOneByOneNoTurnAhead() {
        assertSnapshot(of: widget(.noTurnAhead, size: .oneByOne), as: .image(layout: canvas1x1))
    }

    func testOneByOneTurnImperial() {
        assertSnapshot(of: widget(.turn, size: .oneByOne, unit: .imperial), as: .image(layout: canvas1x1))
    }
}
