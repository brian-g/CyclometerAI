import Foundation
import Testing
@testable import Cyclometer

/// The one bucket-average every dashboard series downsamples through (#399).
@Suite("TimedSample")
struct TimedSampleTests {

    private static func series(_ count: Int) -> [AltitudeSample] {
        (0..<count).map { AltitudeSample(time: Date(timeIntervalSinceReferenceDate: Double($0)), meters: Double($0) * 2) }
    }

    /// Floating-point edges ended one short at counts like 123 and dropped the newest sample (#140 review);
    /// Cadence's chart still had them until this helper replaced it.
    @Test("buckets hold every sample once, in order, newest included", arguments: [60, 120])
    func bucketsPartitionTheSeries(resolution: Int) {
        let all = Self.series(4_000)
        for count in 1...all.count {
            let buckets = Array(all.prefix(count)).buckets(to: resolution)
            #expect(buckets.count == min(count, resolution), "count \(count)")
            #expect(buckets.first?.startIndex == 0, "count \(count)")
            #expect(buckets.last?.endIndex == count, "count \(count)")
            #expect(buckets.allSatisfy { !$0.isEmpty }, "count \(count)")
            #expect(zip(buckets, buckets.dropFirst()).allSatisfy { $0.endIndex == $1.startIndex }, "count \(count)")
        }
    }

    @Test("each bucket is the mean of its time and value")
    func bucketAveragedTakesMeans() {
        let averaged = Self.series(120).bucketAveraged(to: 60)
        #expect(averaged.count == 60)
        #expect(averaged.first == AltitudeSample(time: Date(timeIntervalSinceReferenceDate: 0.5), meters: 1))
        #expect(averaged.last == AltitudeSample(time: Date(timeIntervalSinceReferenceDate: 118.5), meters: 237))
    }

    @Test("a series already within the resolution comes back unchanged")
    func bucketAveragedLeavesAShortSeries() {
        let short = Self.series(60)
        #expect(short.bucketAveraged(to: 60) == short)
    }
}
