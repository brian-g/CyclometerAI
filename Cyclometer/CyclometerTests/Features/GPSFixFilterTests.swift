import Foundation
import Testing
@testable import Cyclometer

@Suite("GPSFixFilter")
struct GPSFixFilterTests {

    @Test("A fix inside the accuracy threshold is recorded")
    func goodFixRecorded() {
        #expect(GPSFixFilter.isTrustworthy(5))
        #expect(GPSFixFilter.isRecordable(horizontalAccuracyMeters: 5, sinceLastRecorded: 1))
    }

    @Test("A fix at exactly the threshold is recorded")
    func thresholdFixRecorded() {
        #expect(GPSFixFilter.isTrustworthy(GPSFixFilter.maxHorizontalAccuracy))
    }

    @Test("A fix worse than the threshold is not recorded")
    func poorFixSuppressed() {
        // The two accuracies the log archive recorded for the 2026-09-06 artefacts.
        #expect(!GPSFixFilter.isTrustworthy(13.2))
        #expect(!GPSFixFilter.isTrustworthy(10.3))
        #expect(!GPSFixFilter.isRecordable(horizontalAccuracyMeters: 13.2, sinceLastRecorded: 1))
    }

    @Test("An invalid fix is never recorded, however long the gap")
    func invalidFixNeverRecorded() {
        // CoreLocation's own signal that the position means nothing — waiting doesn't
        // make it worth writing down.
        for accuracy in [-1.0, 0.0] {
            #expect(!GPSFixFilter.isTrustworthy(accuracy))
            #expect(!GPSFixFilter.isRecordable(
                horizontalAccuracyMeters: accuracy,
                sinceLastRecorded: 10 * GPSFixFilter.maxSuppressedInterval
            ))
        }
    }

    @Test("The backstop takes a poor fix once nothing has been recorded for long enough")
    func backstopRescuesPoorFix() {
        let poor = 15.0
        #expect(!GPSFixFilter.isRecordable(
            horizontalAccuracyMeters: poor,
            sinceLastRecorded: GPSFixFilter.maxSuppressedInterval - 0.5
        ))
        #expect(GPSFixFilter.isRecordable(
            horizontalAccuracyMeters: poor,
            sinceLastRecorded: GPSFixFilter.maxSuppressedInterval
        ))
        #expect(GPSFixFilter.isRecordable(
            horizontalAccuracyMeters: GPSFixFilter.maxBackstopAccuracy,
            sinceLastRecorded: GPSFixFilter.maxSuppressedInterval
        ))
    }

    @Test("A fix worse than the backstop's ceiling waits for the last resort")
    func fixPastCeilingWaitsForLastResort() {
        let worse = GPSFixFilter.maxBackstopAccuracy.nextUp
        #expect(!GPSFixFilter.isRecordable(
            horizontalAccuracyMeters: worse,
            sinceLastRecorded: GPSFixFilter.maxSuppressedInterval
        ))
        #expect(!GPSFixFilter.isRecordable(
            horizontalAccuracyMeters: worse,
            sinceLastRecorded: GPSFixFilter.lastResortInterval - 0.5
        ))
        #expect(GPSFixFilter.isRecordable(
            horizontalAccuracyMeters: worse,
            sinceLastRecorded: GPSFixFilter.lastResortInterval
        ))
    }

    @Test("A ride whose every fix is poor still records a track, at the backstop's or the last resort's cadence",
          arguments: [
            (accuracy: 15.0, interval: GPSFixFilter.maxSuppressedInterval),
            (accuracy: 30.0, interval: GPSFixFilter.lastResortInterval)
          ])
    func allPoorRideRecordsATrack(accuracy: Double, interval: TimeInterval) {
        let recorded = Self.replay(stride(from: 1.0, through: 300.0, by: 1.0).map { ($0, accuracy) })
        // One poor fix a second for five minutes.
        #expect(recorded.count == Int(300 / interval))
        #expect(recorded.first == interval)
    }

    @Test("2026-11-21's start keeps the 14 m and 19 m fixes and drops the 21–47 m ones that drew it 40 m off")
    func november21StartDropsFixesPastCeiling() {
        // Seconds from 11:49:07, the last 2 m fix before accuracy degraded, with each fix the
        // recording log shows: the gate's open/shut lines and the points the GPX kept. Under the
        // old any-accuracy backstop all of 21.3, 31.5, 40.4, 44.3 and 47.1 were recorded.
        let fixes: [(TimeInterval, Double)] = [
            (1, 10.8), (10, 13.9), (11, 15.1), (20, 21.3), (21, 21.8), (30, 31.5), (31, 33.1),
            (41, 40.4), (42, 40.6), (51, 44.3), (52, 43.6), (62, 19.0), (63, 15.1), (65, 8.5),
            (73, 9.0), (83, 47.1), (84, 2.0)
        ]
        #expect(Self.replay(fixes) == [10, 62, 65, 73, 84])
    }

    /// The seconds whose fixes `isRecordable` takes, timed from a recorded point at 0.
    private static func replay(_ fixes: [(TimeInterval, Double)]) -> [TimeInterval] {
        var lastRecorded: TimeInterval = 0
        var recorded: [TimeInterval] = []
        for (second, accuracy) in fixes where GPSFixFilter.isRecordable(
            horizontalAccuracyMeters: accuracy, sinceLastRecorded: second - lastRecorded
        ) {
            recorded.append(second)
            lastRecorded = second
        }
        return recorded
    }

    @Test("WheelCalibration and the recording gate share one accuracy threshold")
    func thresholdIsShared() {
        #expect(WheelCalibration.maxHorizontalAccuracy == GPSFixFilter.maxHorizontalAccuracy)
    }
}
