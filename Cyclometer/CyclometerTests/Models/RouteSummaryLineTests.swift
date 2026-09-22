import Foundation
import Testing
@testable import Cyclometer

@Suite("RouteSummaryLine")
struct RouteSummaryLineTests {

    private func climb(_ category: ClimbCategory) -> Climb {
        Climb(startMeters: 0, lengthMeters: 5_000, gainMeters: 300, averageGradePercent: 6,
              maxGradePercent: 9, topElevationMeters: 400, category: category)
    }

    private func summary(
        distanceMeters: Double = 72_420.48,
        gainMeters: Double? = 1_158.24,
        climbs: [Climb] = [],
        maxGrade: Double = 14,
        character: RouteCharacter = .rolling,
        hasTerrain: Bool = true,
        surface: RouteSurfaceBreakdown? = RouteSurfaceBreakdown(pavedMeters: 900, gravelMeters: 100)
    ) -> RouteSummary {
        var summary = RouteSummary.empty
        summary.distanceMeters = distanceMeters
        summary.elevationGainMeters = gainMeters
        summary.terrain = hasTerrain
            ? RouteTerrainAnalysis(maxGradePercent: maxGrade, climbs: climbs, character: character)
            : nil
        summary.surface = surface
        return summary
    }

    @Test("#252's example, in imperial")
    func imperialExample() {
        let route = summary(climbs: [climb(.cat2), climb(.cat3), climb(.cat2)])
        #expect(RouteSummaryLine.text(for: route, unit: .imperial)
                == "45.0 mi | 3,800 ft gain | 2x Cat 2 climbs | Max 14% grade | Rolling, paved")
    }

    @Test("the same route in metric")
    func metricExample() {
        let route = summary(climbs: [climb(.cat2), climb(.cat3), climb(.cat2)])
        #expect(RouteSummaryLine.text(for: route, unit: .metric)
                == "72.4 km | 1,158 m gain | 2x Cat 2 climbs | Max 14% grade | Rolling, paved")
    }

    @Test("one climb is singular")
    func singleClimb() {
        #expect(RouteSummaryLine.text(for: summary(climbs: [climb(.hc)]), unit: .metric).contains("1x HC climb |"))
    }

    @Test("no categorized climbs leaves the climb segment out")
    func noClimbs() {
        #expect(RouteSummaryLine.text(for: summary(), unit: .metric)
                == "72.4 km | 1,158 m gain | Max 14% grade | Rolling, paved")
    }

    @Test("an even surface split reads as mixed, and an untagged route says nothing")
    func surfaceWording() {
        let mixed = summary(surface: RouteSurfaceBreakdown(pavedMeters: 500, gravelMeters: 500))
        #expect(RouteSummaryLine.text(for: mixed, unit: .metric).hasSuffix("Rolling, mixed surface"))
        let untagged = summary(surface: RouteSurfaceBreakdown(unknownMeters: 1_000))
        #expect(RouteSummaryLine.text(for: untagged, unit: .metric).hasSuffix("| Rolling"))
        #expect(RouteSummaryLine.text(for: summary(surface: nil), unit: .metric).hasSuffix("| Rolling"))
    }

    @Test("a route with no elevation is distance and surface")
    func noElevation() {
        let route = summary(gainMeters: nil, hasTerrain: false)
        #expect(RouteSummaryLine.text(for: route, unit: .metric) == "72.4 km | Paved")
        #expect(RouteSummaryLine.text(for: summary(gainMeters: nil, hasTerrain: false, surface: nil), unit: .metric)
                == "72.4 km")
    }

    @Test("S19's row leaves distance out, which it shows beside the line")
    func withoutDistance() {
        #expect(RouteSummaryLine.text(for: summary(), unit: .metric, includesDistance: false)
                == "1,158 m gain | Max 14% grade | Rolling, paved")
        let bare = summary(gainMeters: nil, hasTerrain: false, surface: nil)
        #expect(RouteSummaryLine.text(for: bare, unit: .metric, includesDistance: false).isEmpty)
    }

    @Test("over 80 characters, max grade goes first, then the climbs")
    func dropOrder() {
        let route = summary(distanceMeters: 1_234_500, gainMeters: 12_345,
                            climbs: Array(repeating: climb(.cat1), count: 12), maxGrade: 25,
                            character: .mountainous,
                            surface: RouteSurfaceBreakdown(pavedMeters: 500, gravelMeters: 500))
        let text = RouteSummaryLine.text(for: route, unit: .metric)
        #expect(text == "1,234.5 km | 12,345 m gain | 12x Cat 1 climbs | Mountainous, mixed surface")
        #expect(text.count <= RouteSummaryLine.maximumLength)
    }

    @Test("no route, however extreme, exceeds 80 characters",
          arguments: UnitSystem.allCases)
    func neverExceedsLimit(unit: UnitSystem) {
        for distance in [1.0, 99_999.0, 9_999_999.0] {
            for count in [1, 99] {
                for category in ClimbCategory.allCases {
                    for character in RouteCharacter.allCases {
                        let route = summary(distanceMeters: distance, gainMeters: 99_999,
                                            climbs: Array(repeating: climb(category), count: count),
                                            maxGrade: 99, character: character,
                                            surface: RouteSurfaceBreakdown(pavedMeters: 1, gravelMeters: 1))
                        #expect(RouteSummaryLine.text(for: route, unit: unit).count <= RouteSummaryLine.maximumLength)
                    }
                }
            }
        }
    }
}
