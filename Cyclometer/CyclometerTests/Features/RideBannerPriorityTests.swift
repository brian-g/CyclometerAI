import Foundation
import Testing
@testable import Cyclometer

/// #197 — the dashboard's one banner slot, now contested by four notices. The order is
/// `RideDashboardView.banner(turn:sourceSwitch:calibration:isOffRoute:)`'s doc comment.
@MainActor
@Suite("Ride dashboard — banner priority")
struct RideBannerPriorityTests {

    private let turn = Maneuver(
        coordinate: RouteFixtures.origin, direction: .right, name: nil, distanceAlongRouteMeters: 0
    )

    @Test("a turn outranks every other notice")
    func turnOutranksEverything() {
        let banner = RideDashboardView.banner(turn: turn, sourceSwitch: "switch", calibration: "wheel", isOffRoute: true)
        #expect(banner?.text == "Turn right")
        #expect(banner?.icon == "arrow.turn.up.right")
    }

    @Test("a speed-source switch outranks calibration and off route")
    func sourceSwitchOutranksCalibrationAndOffRoute() {
        let banner = RideDashboardView.banner(turn: nil, sourceSwitch: "switch", calibration: "wheel", isOffRoute: true)
        #expect(banner?.text == "switch")
        #expect(banner?.icon == "shuffle")
    }

    @Test("calibration outranks off route")
    func calibrationOutranksOffRoute() {
        let banner = RideDashboardView.banner(turn: nil, sourceSwitch: nil, calibration: "wheel", isOffRoute: true)
        #expect(banner?.text == "wheel")
        #expect(banner?.icon == "ruler")
    }

    @Test("off route shows once nothing else is up, and nothing shows when nothing is")
    func offRouteShowsLast() {
        let offRoute = RideDashboardView.banner(turn: nil, sourceSwitch: nil, calibration: nil, isOffRoute: true)
        #expect(offRoute?.text == NavigationFeature.offRouteBannerText)
        #expect(offRoute?.icon == "exclamationmark.triangle")
        #expect(RideDashboardView.banner(turn: nil, sourceSwitch: nil, calibration: nil, isOffRoute: false) == nil)
    }
}
