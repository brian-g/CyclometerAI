import Foundation
import Testing
@testable import Cyclometer

@Suite("AverageSpeedTrend — W2's rising/falling runs (#140)")
struct AverageSpeedTrendTests {
    private func samples(_ values: [Double]) -> [SpeedSample] {
        values.enumerated().map { SpeedSample(time: Date(timeIntervalSinceReferenceDate: Double($0)), mps: $1) }
    }

    @Test("Fewer than two samples draw no line")
    func tooFewSamples() {
        #expect(AverageSpeedTrend.runs([]).isEmpty)
        #expect(AverageSpeedTrend.runs(samples([5])).isEmpty)
    }

    @Test("A steadily climbing average is one rising run")
    func allRising() {
        let s = samples([1, 2, 3])
        #expect(AverageSpeedTrend.runs(s) == [.init(isRising: true, samples: s)])
    }

    @Test("A rise then a fall splits at the peak, which both runs share")
    func riseThenFall() {
        let s = samples([1, 3, 2, 1])
        #expect(AverageSpeedTrend.runs(s) == [
            .init(isRising: true, samples: Array(s[0...1])),
            .init(isRising: false, samples: Array(s[1...3])),
        ])
    }

    @Test("A level stretch continues the run before it")
    func levelContinuesRun() {
        let s = samples([3, 2, 2, 1, 1, 4])
        #expect(AverageSpeedTrend.runs(s) == [
            .init(isRising: false, samples: Array(s[0...4])),
            .init(isRising: true, samples: Array(s[4...5])),
        ])
    }

    @Test("A level start takes the direction of the first change")
    func levelStart() {
        let s = samples([2, 2, 1])
        #expect(AverageSpeedTrend.runs(s) == [.init(isRising: false, samples: s)])
    }
}
