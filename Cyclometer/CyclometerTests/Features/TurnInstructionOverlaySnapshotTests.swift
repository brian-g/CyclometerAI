import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

/// #197 review — the centred turn overlay (Sketch "Sxx - Route overlay"), over a stand-in for the
/// dashboard so that the card's translucency has something to show through it.
final class TurnInstructionOverlaySnapshotTests: XCTestCase {

    private let canvas: SwiftUISnapshotLayout = .fixed(width: 402, height: 300)

    private func overlay(
        _ direction: Maneuver.Direction,
        name: String? = nil,
        scheme: ColorScheme = .light
    ) -> some View {
        ZStack {
            Color.cyBgSecondary
            Text("22.4")
                .font(.cyHeroSpeed)
                .foregroundStyle(Color.cyTextPrimary)
            TurnInstructionOverlay(maneuver: Maneuver(
                coordinate: RouteCoordinate(latitude: 0, longitude: 0, elevationMeters: nil),
                direction: direction,
                name: name,
                distanceAlongRouteMeters: 0
            ))
        }
        .frame(width: 402, height: 300)
        .preferredColorScheme(scheme)
    }

    func testTurnLeft() {
        assertSnapshot(of: overlay(.left), as: .image(layout: canvas))
    }

    func testTurnLeftDark() {
        assertSnapshot(
            of: overlay(.left, scheme: .dark),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .dark))
        )
    }

    func testUTurn() {
        assertSnapshot(of: overlay(.uTurn), as: .image(layout: canvas))
    }

    /// A cue's own words run longer than the design's square: the card grows and the text wraps.
    func testCueWordsWrap() {
        assertSnapshot(of: overlay(.right, name: "Turn right onto County Road S"), as: .image(layout: canvas))
    }

    func testCueWordsWrapDark() {
        assertSnapshot(
            of: overlay(.right, name: "Turn right onto County Road S", scheme: .dark),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .dark))
        )
    }
}
