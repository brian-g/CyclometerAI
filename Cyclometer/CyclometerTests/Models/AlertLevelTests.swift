import Foundation
import Testing
@testable import Cyclometer

@Suite("AlertLevel")
struct AlertLevelTests {

    private static func vehicle(mps: Double) -> RadarTarget {
        RadarTarget(id: UUID(), relativeVelocityMPS: mps, rangeMetres: 40, threatLevel: .allClear)
    }

    @Test("No targets is clear")
    func emptyIsClear() {
        #expect(AlertLevel.level(for: []) == .clear)
    }

    @Test("A single receding vehicle is clear, not advisory")
    func recedingIsClear() {
        #expect(AlertLevel.level(for: [Self.vehicle(mps: -5)]) == .clear)
    }

    @Test("Single-vehicle closing speed maps to the correct level across both boundaries", arguments: [
        (14.9 / 3.6, AlertLevel.advisory),
        (15.0 / 3.6, .caution),   // moderateClosingSpeedKPH lower bound is inclusive
        (29.9 / 3.6, .caution),
        (30.0 / 3.6, .danger)     // dangerClosingSpeedKPH lower bound is inclusive
    ])
    func closingSpeedBoundaries(mps: Double, expected: AlertLevel) {
        #expect(AlertLevel.level(for: [Self.vehicle(mps: mps)]) == expected)
    }

    @Test("Two low-speed approaching vehicles is advisory")
    func twoLowSpeedIsAdvisory() {
        let targets = [Self.vehicle(mps: 2), Self.vehicle(mps: 2)]
        #expect(AlertLevel.level(for: targets) == .advisory)
    }

    @Test("Three low-speed approaching vehicles is caution via the vehicle-count clause")
    func threeLowSpeedIsCaution() {
        let targets = [Self.vehicle(mps: 2), Self.vehicle(mps: 2), Self.vehicle(mps: 2)]
        #expect(AlertLevel.level(for: targets) == .caution)
    }

    @Test("Only approaching vehicles count toward the 3+ threshold, not raw array length")
    func countClauseIgnoresRecedingVehicles() {
        let targets = [Self.vehicle(mps: 2), Self.vehicle(mps: -3), Self.vehicle(mps: -3)]
        #expect(AlertLevel.level(for: targets) == .advisory)
    }

    @Test("A single vehicle at danger speed overrides regardless of how many others are present")
    func dangerOverridesVehicleCount() {
        let targets = [Self.vehicle(mps: 1), Self.vehicle(mps: 1), Self.vehicle(mps: 30 / 3.6)]
        #expect(AlertLevel.level(for: targets) == .danger)
    }
}
