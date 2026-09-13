import Foundation
import Testing
@testable import Cyclometer

/// #197 — the dashboard's one banner slot, contested by three notices. The order is
/// `RideDashboardView.banner(sourceSwitch:calibration:isOffRoute:)`'s doc comment. A turn is not
/// one of them since the review: it has the centred `TurnInstructionOverlay`.
@MainActor
@Suite("Ride dashboard — banner priority")
struct RideBannerPriorityTests {

    @Test("a speed-source switch outranks calibration and off route")
    func sourceSwitchOutranksCalibrationAndOffRoute() {
        let banner = RideDashboardView.banner(sourceSwitch: "switch", calibration: "wheel", isOffRoute: true)
        #expect(banner?.text == "switch")
        #expect(banner?.icon == "shuffle")
    }

    @Test("calibration outranks off route")
    func calibrationOutranksOffRoute() {
        let banner = RideDashboardView.banner(sourceSwitch: nil, calibration: "wheel", isOffRoute: true)
        #expect(banner?.text == "wheel")
        #expect(banner?.icon == "ruler")
    }

    @Test("off route shows once nothing else is up, and nothing shows when nothing is")
    func offRouteShowsLast() {
        let offRoute = RideDashboardView.banner(sourceSwitch: nil, calibration: nil, isOffRoute: true)
        #expect(offRoute?.text == NavigationFeature.offRouteBannerText)
        #expect(offRoute?.icon == "exclamationmark.triangle")
        #expect(RideDashboardView.banner(sourceSwitch: nil, calibration: nil, isOffRoute: false) == nil)
    }
}
