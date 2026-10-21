import Foundation
import SwiftUI
import Testing
@testable import Cyclometer

@Suite("CadenceZone")
struct CadenceZoneTests {

    @Test("RPM maps to the correct default zone across boundaries (#79)", arguments: [
        (1.0, CadenceZone.zone1),   // below Z1's 60 rpm floor still counts as Z1, as HR below resting does
        (59.0, .zone1),
        (69.0, .zone1),
        (69.4, .zone1),             // W5 shows 69
        (69.6, .zone2),             // W5 shows 70, so it counts where S12 lists 70
        (70.0, .zone2),             // a zone's lower bound is inclusive
        (84.0, .zone2),
        (85.0, .zone3),
        (94.0, .zone3),
        (95.0, .zone4),
        (109.0, .zone4),
        (110.0, .zone5),
        (200.0, .zone5)
    ])
    func zoneForRPM(rpm: Double, expected: CadenceZone) {
        #expect(CadenceZoneBoundaries.default.zone(forRPM: rpm) == expected)
    }

    @Test("Custom boundaries move the classification")
    func customBoundaries() throws {
        let zones = try #require(CadenceZoneBoundaries(lowerBoundsRPM: [75, 90, 100, 120]))
        #expect(zones.zone(forRPM: 74) == .zone1)
        #expect(zones.zone(forRPM: 75) == .zone2)
        #expect(zones.zone(forRPM: 119) == .zone4)
        #expect(zones.zone(forRPM: 120) == .zone5)
    }

    @Test("Boundaries must rise strictly between Z1's floor and the chart ceiling", arguments: [
        [70, 85, 95],          // too few
        [70, 85, 95, 110, 120],
        [60, 85, 95, 110],     // Z1 would be empty
        [70, 70, 95, 110],     // Z2 would be empty
        [70, 95, 85, 110],     // out of order
        [70, 85, 95, 150]      // Z5 would start at the chart's ceiling
    ])
    func invalidBoundaries(lowerBounds: [Int]) {
        #expect(CadenceZoneBoundaries(lowerBoundsRPM: lowerBounds) == nil)
    }

    @Test("A per-rpm tally sorts into zones, leaving out zones with no time")
    func zoneSecondsFromTally() throws {
        let tally: [Int: TimeInterval] = [40: 3, 69: 2, 70: 1.5, 84: 4, 110: 6]
        #expect(CadenceZoneBoundaries.default.zoneSeconds(tally) == [.zone1: 5, .zone2: 5.5, .zone5: 6])

        // The same tally against other zones: the time moves with the boundaries.
        let custom = try #require(CadenceZoneBoundaries(lowerBoundsRPM: [75, 90, 100, 120]))
        #expect(custom.zoneSeconds(tally) == [.zone1: 6.5, .zone2: 4, .zone4: 6])
        #expect(CadenceZoneBoundaries.default.zoneSeconds([:]).isEmpty)
    }

    @Test("Display ranges: Z1 from its floor, inclusive uppers, Z5 open-ended")
    func displayRanges() {
        let zones = CadenceZoneBoundaries.default
        #expect(CadenceZone.allCases.map(zones.rangeText) == ["60-69", "70-84", "85-94", "95-109", "110+"])
    }

    @Test("Bands are contiguous and cover 0...ceiling without gaps")
    func bandsAreContiguous() {
        let ceiling = 150.0
        let ranges = CadenceZone.allCases.map { CadenceZoneBoundaries.default.bandRange(for: $0, ceiling: ceiling) }
        #expect(ranges.first?.lowerBound == 0)
        #expect(ranges.last?.upperBound == ceiling)
        for (a, b) in zip(ranges, ranges.dropFirst()) {
            #expect(a.upperBound == b.lowerBound)
        }
    }

    @Test("A ceiling below a boundary clamps the bands rather than inverting them")
    func lowCeilingClamps() {
        let ranges = CadenceZone.allCases.map { CadenceZoneBoundaries.default.bandRange(for: $0, ceiling: 80) }
        #expect(ranges.allSatisfy { $0.lowerBound <= $0.upperBound && $0.upperBound <= 80 })
    }

    @Test("Stepping moves one boundary, and refuses to cross a neighbour or a limit")
    func stepping() throws {
        let zones = CadenceZoneBoundaries.default
        #expect(zones.stepping(afterZone: .zone2, by: 1)?.lowerBoundsRPM == [70, 86, 95, 110])
        #expect(zones.stepping(afterZone: .zone2, by: -1)?.lowerBoundsRPM == [70, 84, 95, 110])
        // There is no boundary after Z5.
        #expect(zones.stepping(afterZone: .zone5, by: 1) == nil)

        let tight = try #require(CadenceZoneBoundaries(lowerBoundsRPM: [61, 62, 63, 149]))
        #expect(tight.stepping(afterZone: .zone1, by: -1) == nil)   // Z1 would be empty
        #expect(tight.stepping(afterZone: .zone1, by: 1) == nil)    // Z2 would be empty
        #expect(tight.stepping(afterZone: .zone4, by: 1) == nil)    // Z5 would leave the chart
    }

    @Test("Zones take the HR zone colours and S12's names")
    func colorsAndNames() {
        for zone in CadenceZone.allCases {
            #expect(zone.color == Color.hrZone(zone.rawValue))
        }
        #expect(CadenceZone.allCases.map(\.displayName) == ["Recovery", "Endurance", "Steady State", "Race Pace", "Sprint"])
    }

    @Test("Boundaries round-trip through JSON, and an invalid document fails to decode")
    func coding() throws {
        let custom = try #require(CadenceZoneBoundaries(lowerBoundsRPM: [72, 88, 98, 115]))
        let data = try JSONEncoder().encode(custom)
        #expect(try JSONDecoder().decode(CadenceZoneBoundaries.self, from: data) == custom)

        let invalid = Data(#"{"lowerBoundsRPM":[90,80,95,110]}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CadenceZoneBoundaries.self, from: invalid)
        }
    }

    @Test("Preferences written before #79, or holding invalid zones, decode with the defaults")
    func preferencesFallBack() throws {
        let missing = try JSONDecoder().decode(AppPreferences.self, from: Data(#"{"isAutoDimEnabled":false}"#.utf8))
        #expect(missing.cadenceZones == .default)
        #expect(missing.isAutoDimEnabled == false)

        let invalid = Data(#"{"isAutoDimEnabled":false,"cadenceZones":{"lowerBoundsRPM":[1]}}"#.utf8)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: invalid)
        #expect(decoded.cadenceZones == .default)
        #expect(decoded.isAutoDimEnabled == false)
    }
}
