import Foundation
import Testing
@testable import Cyclometer

/// #197 — the dashboard's one banner slot, contested by four notices. The order is
/// `RideDashboardView.banner(sourceSwitch:calibration:rain:isOffRoute:)`'s doc comment. A turn is
/// not one of them since the review: it has the centred `TurnInstructionOverlay`.
@MainActor
@Suite("Ride dashboard — banner priority")
struct RideBannerPriorityTests {
    private let rain: RideDashboardView.Banner = (
        text: "Rain 70% · 18.4 km ahead", icon: "cloud.rain.fill", spokenText: "Rain, 70% chance, 18.4 kilometers ahead"
    )

    @Test("a speed-source switch outranks calibration, rain and off route")
    func sourceSwitchOutranksCalibrationAndOffRoute() {
        let banner = RideDashboardView.banner(sourceSwitch: "switch", calibration: "wheel", rain: rain, isOffRoute: true)
        #expect(banner?.text == "switch")
        #expect(banner?.icon == "shuffle")
        #expect(banner?.spokenText == nil, "#568: never the outranked rain's words")
    }

    @Test("calibration outranks rain and off route")
    func calibrationOutranksOffRoute() {
        let banner = RideDashboardView.banner(sourceSwitch: nil, calibration: "wheel", rain: rain, isOffRoute: true)
        #expect(banner?.text == "wheel")
        #expect(banner?.icon == "ruler")
        #expect(banner?.spokenText == nil, "#568: never the outranked rain's words")
    }

    /// #152: rain is up for four seconds; off route lasts until the rider rejoins.
    @Test("rain ahead outranks off route")
    func rainOutranksOffRoute() {
        let banner = RideDashboardView.banner(sourceSwitch: nil, calibration: nil, rain: rain, isOffRoute: true)
        #expect(banner?.text == rain.text)
        #expect(banner?.icon == rain.icon)
        #expect(banner?.spokenText == rain.spokenText, "#568: VoiceOver reads the distance in words")
    }

    @Test("off route shows once nothing else is up, and nothing shows when nothing is")
    func offRouteShowsLast() {
        let offRoute = RideDashboardView.banner(sourceSwitch: nil, calibration: nil, rain: nil, isOffRoute: true)
        #expect(offRoute?.text == NavigationFeature.offRouteBannerText)
        #expect(offRoute?.icon == "exclamationmark.triangle")
        #expect(offRoute?.spokenText == nil, "#568: read as written, as before")
        #expect(RideDashboardView.banner(sourceSwitch: nil, calibration: nil, rain: nil, isOffRoute: false) == nil)
    }
}
