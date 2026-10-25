import Foundation
import Testing
@testable import Cyclometer

@Suite("Watermark — the dashboard watermarks' shared time axis")
struct WatermarkTests {
    private struct Reading { let time: Date; let value: Double }

    private func at(_ seconds: Double) -> Date { Date(timeIntervalSinceReferenceDate: seconds) }

    private func readings(_ seconds: some Sequence<Int>, value: (Int) -> Double = { _ in 0 }) -> [Reading] {
        seconds.map { Reading(time: at(Double($0)), value: value($0)) }
    }

    private func points(_ readings: [Reading], over window: ClosedRange<Date>) -> [WatermarkPoint] {
        Watermark.points(readings, over: window, time: \.time, value: \.value)
    }

    // MARK: - Window

    @Test("No readings in any series, no window")
    func windowNeedsAReading() {
        #expect(Watermark.window(oldest: [nil, nil], newest: [nil, nil], span: 3600) == nil)
    }

    @Test("The window runs from the oldest reading in any series to the newest")
    func windowSpansEverySeries() {
        let window = Watermark.window(oldest: [at(100), at(40), nil], newest: [at(900), at(500), nil], span: 3600)
        #expect(window == at(40)...at(900))
    }

    @Test("A quiet series' untrimmed readings can't stretch the window past the span")
    func windowClampsToSpan() {
        // Cadence went quiet at 100 s and never trimmed; speed read on to 5000 s.
        let window = Watermark.window(oldest: [at(0), at(0)], newest: [at(5000), at(100)], span: 3600)
        #expect(window == at(1400)...at(5000))
    }

    // MARK: - Points

    @Test("Each point is its bucket's mean time and value")
    func bucketMeans() {
        // 2 s buckets over 120 s, a reading a second.
        let points = points(readings(0..<120) { Double($0) * 2 }, over: at(0)...at(120))
        #expect(points.count == Watermark.bucketCount)
        #expect(points.first == WatermarkPoint(time: at(0.5), value: 1, run: 0))
        #expect(points.last == WatermarkPoint(time: at(118.5), value: 237, run: 0))
    }

    @Test("An hour at 1 Hz is at most bucketCount points")
    func boundedOverAnHour() {
        let points = points(readings(0...3600) { _ in 6 }, over: at(0)...at(3600))
        #expect(points.count == Watermark.bucketCount)
        #expect(points.allSatisfy { $0.value == 6 && $0.run == 0 })
    }

    @Test("The newest reading is always plotted")
    func keepsNewestReading() {
        for count in [61, 123, 245, 490, 3_600] {
            let all = readings(0..<count) + [Reading(time: at(Double(count)), value: 1_000)]
            #expect(points(all, over: at(0)...at(Double(count))).last!.value > 0, "count \(count + 1)")
        }
    }

    @Test("Readings outside the window are left out")
    func dropsReadingsOutsideWindow() {
        let points = points(readings([0, 50, 100]) { Double($0) }, over: at(10)...at(90))
        #expect(points.map(\.value) == [50])
    }

    @Test("A silence over gapSeconds starts a new run; one of exactly gapSeconds doesn't")
    func gapStartsRun() {
        let gap = Int(Watermark.gapSeconds)
        #expect(points(readings([0, gap]), over: at(0)...at(Double(gap))).map(\.run) == [0, 0])
        #expect(points(readings([0, gap + 1]), over: at(0)...at(Double(gap + 1))).map(\.run) == [0, 1])
    }

    @Test("No point averages across a gap, even inside one bucket")
    func bucketNeverMixesRuns() {
        // 600 s buckets: both readings fall in the first, either side of a 300 s silence.
        let points = points(readings([0, 300]) { $0 == 0 ? 10 : 90 }, over: at(0)...at(36_000))
        #expect(points == [
            WatermarkPoint(time: at(0), value: 10, run: 0),
            WatermarkPoint(time: at(300), value: 90, run: 1),
        ])
    }

    @Test("A window of one instant puts its reading in the one bucket")
    func zeroWidthWindow() {
        #expect(points(readings([5]) { _ in 3 }, over: at(5)...at(5)) == [WatermarkPoint(time: at(5), value: 3, run: 0)])
    }

    @Test("The plot domain is the window, else the points' span, never zero-wide")
    func plotDomain() {
        let points = [WatermarkPoint(time: at(10), value: 1, run: 0), WatermarkPoint(time: at(70), value: 1, run: 0)]
        #expect(points.plotDomain(at(0)...at(100)) == at(0)...at(100))
        #expect(points.plotDomain(nil) == at(10)...at(70))
        #expect([WatermarkPoint]().plotDomain(nil) == at(0)...at(1))
        #expect(points.plotDomain(at(5)...at(5)) == at(5)...at(6))
    }

    @Test("Lone points are the runs of one, which a line can't draw")
    func lonePoints() {
        let points = [0, 1, 1, 2, 3, 3].enumerated().map {
            WatermarkPoint(time: at(Double($0.offset)), value: Double($0.offset), run: $0.element)
        }
        #expect(points.lonePoints.map(\.run) == [0, 2])
        #expect([WatermarkPoint(time: at(0), value: 1, run: 0)].lonePoints.count == 1)
        #expect([WatermarkPoint]().lonePoints.isEmpty)
    }

    @Test("Apple Watch heart rate minutes apart is all lone points, so W4 still draws it")
    func sparseHealthKitHeartRate() {
        // Without a Watch workout, HealthKit lands a reading every few minutes.
        let points = points(readings(stride(from: 0, through: 3_600, by: 300)) { _ in 120 }, over: at(0)...at(3_600))
        #expect(points.count == 13)
        #expect(points.lonePoints == points)
    }

    // MARK: - The ride that found it

    /// 2026-10-24: both Wahoo sensors slept through a stop. Speed fell back to GPS and read on at 1 Hz;
    /// cadence had no readings at all. Plotted by index, W5 squeezed the stop out and the two traces
    /// stopped lining up (IMG_5589). On the shared axis, speed draws the stop and cadence breaks across
    /// the same stretch of time.
    @Test("A cadence sensor asleep through a stop breaks where speed reads zero")
    func sleepingSensorLinesUpWithSpeed() throws {
        var state = ActiveRideFeature.State()
        let start = Date(timeIntervalSince1970: 0)
        let stop = 1_740..<2_700        // stopped, 11:29–11:45 relative to 11:00
        let silent = 1_828..<2_714      // cadence sensor asleep, 11:30:28–11:45:14
        state.speed.speedSamples = (0...3_600).map {
            SpeedSample(time: start.addingTimeInterval(Double($0)), mps: stop.contains($0) ? 0 : 6)
        }
        state.cadence.cadenceSamples = (0...3_600).filter { !silent.contains($0) }.map {
            CadenceSample(time: start.addingTimeInterval(Double($0)), rpm: stop.contains($0) ? 0 : 85)
        }

        let window = try #require(state.watermarkWindow)
        #expect(window == start...start.addingTimeInterval(3_600))

        let speed = state.speedWatermark
        #expect(Set(speed.map(\.run)) == [0])
        let cadence = state.cadenceWatermark
        #expect(Set(cadence.map(\.run)) == [0, 1])

        // Cadence's break sits inside the stretch where speed reads zero.
        let beforeBreak = try #require(cadence.last { $0.run == 0 }).time
        let afterBreak = try #require(cadence.first { $0.run == 1 }).time
        let stopped = speed.filter { $0.value == 0 }.map(\.time)
        #expect(beforeBreak <= start.addingTimeInterval(Double(silent.lowerBound)))
        #expect(afterBreak >= start.addingTimeInterval(Double(silent.upperBound)))
        #expect(stopped.contains { $0 > beforeBreak && $0 < afterBreak })
    }
}
