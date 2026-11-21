import Foundation

/// Whether a GPS fix is trustworthy enough to be recorded — the thresholds and the
/// decision, with no state, clock or storage, so it can be exercised directly (#210).
///
/// The premise: `TrackPointRecorderFeature` writes a point every second from whatever
/// coordinate `ActiveRideFeature` last saw, with no reference to how good the fix behind
/// it was. On 2026-09-06 that recorded three seconds in which the rider's position crawled
/// 0.3–0.8 m against a speed channel reporting 3.1 m/s and then jumped 20.1 m — the whole
/// run inside a window `WheelCalibrationFeature` had already shut its own gate on
/// ("calibration gps gate shut — accuracy 10.3 m"). The app knew the fix was untrustworthy
/// and wrote it to the track anyway.
///
/// The remedy is to record *nothing* across such a window rather than to substitute a
/// guess: a consumer straight-lines the gap, which is close to the truth for a rider who
/// was on the road the whole time. What is not the remedy is filtering on how far the
/// position jumped — the jump at the end of one of these windows is the fix catching up
/// with ground the rider genuinely covered, and every one of them on that ride is
/// consistent in both bearing and distance with the speed channel.
enum GPSFixFilter {
    /// Fixes worse than this are unreliable. The threshold `WheelCalibration` pauses its
    /// window on, defined here so the two gates cannot drift apart.
    static let maxHorizontalAccuracy = 10.0

    /// Longest the gate may suppress recording before it takes a fix worse than
    /// `maxHorizontalAccuracy`, as long as that fix is within `maxBackstopAccuracy`.
    ///
    /// Without it a ride spent under heavy tree cover — where accuracy can sit above the
    /// threshold for minutes — would record no track at all, which is a far worse outcome
    /// for the rider than a coarse one. Ten seconds keeps the degraded track recognisable
    /// while still discarding ~90% of the points in such a stretch.
    static let maxSuppressedInterval: TimeInterval = 10

    /// The worst fix the backstop takes. Anything worse waits for `lastResortInterval`.
    ///
    /// A fix's error is about its reported accuracy, and under cover the errors lean one way, so
    /// a run of 20–45 m fixes draws a plausible line beside the road rather than scatter. On
    /// 2026-11-21 the first 300 m of the ride came out 27–40 m off the rider's return over the
    /// same ground; the straight line from the last good point to the next was within 7 m.
    /// Replaying 12 rides, every backstop fix worse than 20 m sat off the line its neighbours
    /// drew, none on a bend the rider took, and the longest stretch it leaves straight-lined
    /// is 52 s / 263 m.
    static let maxBackstopAccuracy = 20.0

    /// Longest the gate may go without recording before it takes any valid fix, however poor.
    /// Keeps a ride whose every fix is worse than `maxBackstopAccuracy` from recording no track
    /// at all. Above the longest such stretch seen (52 s), so no recorded ride reaches it.
    static let lastResortInterval: TimeInterval = 60

    /// Whether a fix of this accuracy may be recorded.
    ///
    /// CoreLocation reports a negative `horizontalAccuracy` when the position is invalid,
    /// and 0 is `ActiveRideFeature.State`'s "no fix yet" default; neither is a measurement.
    static func isTrustworthy(_ horizontalAccuracyMeters: Double) -> Bool {
        horizontalAccuracyMeters > 0 && horizontalAccuracyMeters <= maxHorizontalAccuracy
    }

    /// Whether this fix may be recorded, given how long it has been since one was.
    ///
    /// `sinceLastRecorded` is measured from the last recorded point, or from ride start
    /// while there is none — so a ride whose every fix is poor still records a track, at the
    /// backstop's cadence or, worse than `maxBackstopAccuracy`, the last resort's, rather than
    /// an empty one.
    ///
    /// Neither rescues an *invalid* fix: a negative accuracy means CoreLocation is telling us
    /// the position itself is meaningless, and no amount of waiting makes it worth writing
    /// down.
    static func isRecordable(
        horizontalAccuracyMeters: Double,
        sinceLastRecorded: TimeInterval
    ) -> Bool {
        guard horizontalAccuracyMeters > 0 else { return false }
        if isTrustworthy(horizontalAccuracyMeters) { return true }
        if horizontalAccuracyMeters <= maxBackstopAccuracy {
            return sinceLastRecorded >= maxSuppressedInterval
        }
        return sinceLastRecorded >= lastResortInterval
    }
}
