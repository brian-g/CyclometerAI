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

    @Test("Wobble smaller than one step of the number never turns the line (#140 review)")
    func wobbleStaysOneRun() {
        let step = AverageSpeedTrend.turnThresholdMPS
        let s = samples([5, 5 + step * 2, 5 + step * 1.5, 5 + step * 2.2, 5 + step * 1.4, 5 + step * 2.4])
        #expect(AverageSpeedTrend.runs(s) == [.init(isRising: true, samples: s)])
    }

    @Test("A slow decline turns the line at the peak once it adds up past one step")
    func slowDeclineTurnsAtPeak() {
        let step = AverageSpeedTrend.turnThresholdMPS
        // Peak at index 2, then four declines of half a step each.
        let s = samples([5, 5 + step * 2, 5 + step * 3] + (1...4).map { 5 + step * (3 - Double($0) / 2) })
        #expect(AverageSpeedTrend.runs(s) == [
            .init(isRising: true, samples: Array(s[0...2])),
            .init(isRising: false, samples: Array(s[2...])),
        ])
    }

    @Test("A level start takes the direction of the first change")
    func levelStart() {
        let s = samples([2, 2, 1])
        #expect(AverageSpeedTrend.runs(s) == [.init(isRising: false, samples: s)])
    }
}

@Suite("AverageSpeedDashboardWidget — W2's shared time window (#140 review)")
struct AverageSpeedPlottedSeriesTests {
    private func sample(_ minute: Double, _ mps: Double) -> SpeedSample {
        SpeedSample(time: Date(timeIntervalSinceReferenceDate: minute * 60), mps: mps)
    }

    @Test("Average samples older than the watermark's oldest reading are dropped")
    func averageTrimmedToWatermarkWindow() {
        // A stop: speed readings kept trimming to the last hour (from minute 30), while the
        // average, gaining nothing at rest, still holds minutes 0–60.
        let speed = [sample(30, 0), sample(90, 0)]
        let average = [sample(0, 5), sample(29, 6), sample(30, 6), sample(60, 7)]
        let series = AverageSpeedDashboardWidget.plottedSeries(speed: speed, average: average)
        #expect(series.speed == speed)
        #expect(series.average == [sample(30, 6), sample(60, 7)])
    }

    @Test("With no speed readings the average is kept whole")
    func noWatermarkKeepsAverage() {
        let average = [sample(0, 5), sample(1, 6)]
        #expect(AverageSpeedDashboardWidget.plottedSeries(speed: [], average: average).average == average)
    }
}
