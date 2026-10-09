import Testing
import Foundation
@testable import Cyclometer

/// #145 — W4's ▲/▼: the last 10 s of readings against the 20 s before them.
@Suite("Heart Rate Trend")
struct HeartRateTrendTests {

    private let start = Date(timeIntervalSince1970: 1_000_000)

    /// One reading a second for 30 s: `baseline` for the first 20, then `recent`.
    private func strap(baseline: Int, recent: Int) -> [HeartRateSample] {
        (0..<30).map { HeartRateSample(time: start.addingTimeInterval(Double($0)), bpm: $0 < 20 ? baseline : recent) }
    }

    @Test func risingAndFalling() {
        #expect(HeartRateTrend(strap(baseline: 140, recent: 145)) == .up)
        #expect(HeartRateTrend(strap(baseline: 145, recent: 140)) == .down)
    }

    /// Under `thresholdBPM` is a strap's wander, not a trend.
    @Test func smallChangeIsSteady() {
        #expect(HeartRateTrend(strap(baseline: 140, recent: 142)) == .steady)
        #expect(HeartRateTrend(strap(baseline: 140, recent: 143)) == .up)
    }

    /// Too little to compare — a ride seconds old, or an Apple Watch sampling minutes apart.
    @Test func sparseOrEmptyIsSteady() {
        #expect(HeartRateTrend([]) == .steady)
        #expect(HeartRateTrend(Array(strap(baseline: 140, recent: 160).suffix(5))) == .steady)
        let watch = [HeartRateSample(time: start, bpm: 120),
                     HeartRateSample(time: start.addingTimeInterval(180), bpm: 150)]
        #expect(HeartRateTrend(watch) == .steady)
    }

    /// Counted back from the newest reading, so readings older than the baseline don't count.
    @Test func olderReadingsAreIgnored() {
        let old = (0..<60).map { HeartRateSample(time: start.addingTimeInterval(Double($0)), bpm: 100) }
        let flat = (60..<90).map { HeartRateSample(time: start.addingTimeInterval(Double($0)), bpm: 150) }
        #expect(HeartRateTrend(old + flat) == .steady)
    }
}
