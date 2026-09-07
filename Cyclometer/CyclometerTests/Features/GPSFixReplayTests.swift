import CoreLocation
import Foundation
import Testing
@testable import Cyclometer

/// Replays the 566 GPS fixes of the 2026-09-06 ride through `GPSFixFilter` at their own
/// one-second spacing (#210).
///
/// `GPSFixFilterTests` pins each rule in isolation; this suite pins the outcome against what
/// the hardware actually produced — including the four seconds the log archive puts above
/// the accuracy threshold, whose position crawled and then snapped forward.
@Suite("GPSFixFilter — 2026-09-06 track replay")
struct GPSFixReplayTests {

    private struct Replay {
        var recorded: [GPSFixReplayFixtures.Fix] = []
        var suppressed: [GPSFixReplayFixtures.Fix] = []
    }

    /// Feeds the track through the filter one second at a time, holding the backstop clock
    /// the way `ActiveRideFeature` does: measured from the last recorded point, or from ride
    /// start while there is none.
    private static func replay() -> Replay {
        var result = Replay()
        var lastRecorded = 0.0
        for fix in GPSFixReplayFixtures.track {
            let recordable = GPSFixFilter.isRecordable(
                horizontalAccuracyMeters: fix.accuracy,
                sinceLastRecorded: Double(fix.t) - lastRecorded
            )
            if recordable {
                result.recorded.append(fix)
                lastRecorded = Double(fix.t)
            } else {
                result.suppressed.append(fix)
            }
        }
        return result
    }

    private static func distance(_ fixes: [GPSFixReplayFixtures.Fix]) -> Double {
        zip(fixes, fixes.dropFirst()).reduce(0) { total, pair in
            total + CLLocation(latitude: pair.0.lat, longitude: pair.0.lon)
                .distance(from: CLLocation(latitude: pair.1.lat, longitude: pair.1.lon))
        }
    }

    @Test("Exactly the fixes the app judged untrustworthy are suppressed")
    func suppressesOnlyPoorFixes() {
        let replay = Self.replay()
        #expect(Set(replay.suppressed.map(\.t)) == GPSFixReplayFixtures.poorAccuracySeconds)
        #expect(replay.recorded.count == GPSFixReplayFixtures.track.count - 4)
    }

    @Test("No recorded point comes from a fix above the accuracy threshold")
    func everyRecordedPointIsTrustworthy() {
        // The backstop could in principle admit one, but this ride never goes 10 s without
        // a good fix — its worst run is the three seconds at t+235.
        for fix in Self.replay().recorded {
            #expect(fix.accuracy <= GPSFixFilter.maxHorizontalAccuracy)
        }
    }

    @Test("Suppression does not shorten the ride")
    func distanceIsPreserved() {
        let full = Self.distance(GPSFixReplayFixtures.track)
        let recorded = Self.distance(Self.replay().recorded)
        // 3259.9 m unfiltered. The suppressed points sit almost exactly on the line between
        // their neighbours — the artefact is *when* the position advances, not where it ends
        // up — so removing them moves the total by centimetres, not by the tens of metres a
        // filter that dropped good fixes would cost.
        #expect(abs(full - 3259.9) < 1.0)
        #expect(abs(recorded - full) / full < 0.001)
    }

    @Test("The crawl-then-snap seconds no longer carry a timestamp")
    func snapSecondsAreNotRecorded() {
        let recorded = Set(Self.replay().recorded.map(\.t))
        // t+237 is the 20.1 m advance against a reported 3.1 m/s, and t+235–236 the crawl
        // before it; t+238 is the first fix the calibration gate called good again.
        #expect(!recorded.contains(235))
        #expect(!recorded.contains(236))
        #expect(!recorded.contains(237))
        #expect(recorded.contains(234))
        #expect(recorded.contains(238))
    }
}
