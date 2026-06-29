import Testing
@testable import Cyclometer

@Suite("CadenceZone")
struct CadenceZoneTests {

    @Test("RPM maps to the correct zone across boundaries", arguments: [
        (0.0, CadenceZone.grinding),
        (69.0, .grinding),
        (70.0, .transition),   // lower bound is inclusive
        (84.0, .transition),
        (85.0, .optimal),
        (99.0, .optimal),
        (100.0, .overspin),
        (130.0, .overspin)
    ])
    func zoneForRPM(rpm: Double, expected: CadenceZone) {
        #expect(CadenceZone.zone(forRPM: rpm) == expected)
    }

    @Test("rpmRange is contiguous and covers 0...ceiling without gaps")
    func rangesAreContiguous() {
        let ceiling = 130.0
        let ranges = CadenceZone.allCases.map { $0.rpmRange(ceiling: ceiling) }
        #expect(ranges.first?.lowerBound == 0)
        #expect(ranges.last?.upperBound == ceiling)
        for (a, b) in zip(ranges, ranges.dropFirst()) {
            #expect(a.upperBound == b.lowerBound)
        }
    }

    @Test("Each zone exposes a distinct treatment colour and a label")
    func colorsAndLabels() {
        #expect(CadenceZone.grinding.color == .cyRatingOkay)
        #expect(CadenceZone.optimal.color == .cyRatingGood)
        #expect(CadenceZone.overspin.color == .cyRatingBad)
        #expect(CadenceZone.transition.color == .cyTextTertiary)
        #expect(CadenceZone.optimal.label == "85–100")
    }
}
