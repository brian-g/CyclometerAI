import CoreGraphics
import Foundation
import Testing
@testable import Cyclometer

/// #333 — which touch on the dim blocker wakes the screen:
/// `AutoDimWindowBridge.isWakeTap(translation:duration:)`.
@MainActor
@Suite("Auto-dim — wake tap")
struct WakeTapTests {

    private func wakes(travel: CGSize, held seconds: TimeInterval) -> Bool {
        AutoDimWindowBridge.isWakeTap(translation: travel, duration: seconds)
    }

    @Test("a quick, still tap wakes")
    func quickTapWakes() {
        #expect(wakes(travel: CGSize(width: 2, height: 3), held: 0.1))
    }

    @Test("a touch that moves past the travel limit is a swipe, and doesn't wake")
    func swipeDoesNotWake() {
        #expect(!wakes(travel: CGSize(width: 0, height: AutoDimWindowBridge.wakeTapMaxTravel + 1), held: 0.1))
        #expect(!wakes(travel: CGSize(width: 8, height: 8), held: 0.1))
    }

    @Test("a touch held to the long-press threshold doesn't wake")
    func longPressDoesNotWake() {
        #expect(!wakes(travel: .zero, held: AutoDimWindowBridge.wakeTapMaxDuration))
        #expect(!wakes(travel: .zero, held: 2))
    }

    @Test("the travel limit counts as a tap")
    func travelEdge() {
        #expect(wakes(travel: CGSize(width: AutoDimWindowBridge.wakeTapMaxTravel, height: 0), held: 0.1))
    }
}
