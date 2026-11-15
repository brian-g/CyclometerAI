import Foundation
import Testing
@testable import Cyclometer

/// #197 — the dashboard's one banner slot, contested by four notices. The order is
/// `RideDashboardView.banner(sourceSwitch:calibrationMM:rain:unitSystem:isOffRoute:)`'s doc comment. A turn is
/// not one of them since the review: it has the centred `TurnInstructionOverlay`.
@MainActor
@Suite("Ride dashboard — banner priority")
struct RideBannerPriorityTests {
    private let rain = RainAhead(
        chance: 0.7, condition: .rain, isDaylight: true, distanceAheadMeters: 18_400, arrival: .now
    )

    private func banner(
        sourceSwitch: String? = nil, calibrationMM: Int? = nil, rain: RainAhead? = nil, isOffRoute: Bool = false
    ) -> RideBanner? {
        RideDashboardView.banner(
            sourceSwitch: sourceSwitch, calibrationMM: calibrationMM, rain: rain, unitSystem: .metric, isOffRoute: isOffRoute
        )
    }

    @Test("a speed-source switch outranks calibration, rain and off route")
    func sourceSwitchOutranksCalibrationAndOffRoute() {
        let banner = banner(sourceSwitch: "switch", calibrationMM: 2145, rain: rain, isOffRoute: true)
        #expect(banner?.text == "switch")
        #expect(banner?.icon == "shuffle")
        #expect(banner?.spokenWords == "switch", "#568: never an outranked notice's words")
    }

    @Test("calibration outranks rain and off route, and speaks its unit in words")
    func calibrationOutranksOffRoute() {
        let banner = banner(calibrationMM: 2145, rain: rain, isOffRoute: true)
        #expect(banner?.text == WheelCalibration.bannerText(mm: 2145))
        #expect(banner?.icon == "ruler")
        #expect(banner?.spokenWords == WheelCalibration.spokenBannerText(mm: 2145), "#568")
    }

    /// #152: rain is up for four seconds; off route lasts until the rider rejoins.
    @Test("rain ahead outranks off route, and speaks its distance in words")
    func rainOutranksOffRoute() {
        let banner = banner(rain: rain, isOffRoute: true)
        #expect(banner?.text == rain.bannerText(unitSystem: .metric))
        #expect(banner?.icon == rain.symbolName)
        #expect(banner?.spokenWords == rain.spokenText(unitSystem: .metric), "#568")
    }

    @Test("off route shows once nothing else is up, and nothing shows when nothing is")
    func offRouteShowsLast() {
        let offRoute = banner(isOffRoute: true)
        #expect(offRoute?.text == NavigationFeature.offRouteBannerText)
        #expect(offRoute?.icon == "exclamationmark.triangle")
        #expect(offRoute?.spokenWords == NavigationFeature.offRouteBannerText, "#568: read as written")
        #expect(banner() == nil)
    }
}
