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
        let poor = 25.0
        #expect(!GPSFixFilter.isRecordable(
            horizontalAccuracyMeters: poor,
            sinceLastRecorded: GPSFixFilter.maxSuppressedInterval - 0.5
        ))
        #expect(GPSFixFilter.isRecordable(
            horizontalAccuracyMeters: poor,
            sinceLastRecorded: GPSFixFilter.maxSuppressedInterval
        ))
    }

    @Test("A ride whose every fix is poor still records a track, at the backstop's cadence")
    func allPoorRideRecordsATrack() {
        var lastRecorded: TimeInterval = 0
        var recorded: [TimeInterval] = []
        // One poor fix a second for five minutes.
        for second in stride(from: 1.0, through: 300.0, by: 1.0) {
            guard GPSFixFilter.isRecordable(
                horizontalAccuracyMeters: 30,
                sinceLastRecorded: second - lastRecorded
            ) else { continue }
            recorded.append(second)
            lastRecorded = second
        }
        #expect(!recorded.isEmpty)
        #expect(recorded.count == 30)
        #expect(recorded.first == GPSFixFilter.maxSuppressedInterval)
    }

    @Test("WheelCalibration and the recording gate share one accuracy threshold")
    func thresholdIsShared() {
        #expect(WheelCalibration.maxHorizontalAccuracy == GPSFixFilter.maxHorizontalAccuracy)
    }
}
