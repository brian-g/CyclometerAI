import Foundation

/// Whether a displayed speed reading may become the ride's max (#540): the thresholds and the
/// decision, with no state, clock or storage of its own, so it can be exercised directly.
///
/// The max only ever rises, so one bad reading would stay the max for the rest of the ride and
/// in the saved ride, and would grow the speed gauge's scale for good (#534). The speed the rider
/// sees is not gated; only what the max takes is.
///
/// Two checks, because the two speed sources go wrong in different ways:
///
/// - **GPS reports its own error.** CoreLocation: "`speedAccuracy` — Returns the speed accuracy
///   of the location in m/s. Returns -1 if invalid", and "The lower the value the more precise
///   the speed is. A negative accuracy value indicates an invalid speed." A reading whose
///   accuracy is invalid, or wider than `maxGPSSpeedAccuracyMPS`, never counts. The simulator's
///   simulated location (`simctl location`) reports a valid speed with `speedAccuracy` −1, so a
///   GPS-only ride there never sets a max.
/// - **A bicycle can only speed up so fast.** A reading must be reachable from every displayed
///   reading of the last `window`: no more than `maxAccelerationMPS2` per second above it, plus
///   `readingSlackMPS`. And there must be at least one such reading to measure it against. This
///   is the only check a wheel sensor gets, since CSC has no accuracy field. `CSCCalculator`
///   already drops a zero event-time delta, re-primes after a stop and on a reconnect, and caps a
///   reading at 15 rev/s, but 15 rev/s is still ~113 km/h.
///
/// Why "every reading of the window" rather than "the previous reading": a spike that lasts two
/// seconds would pass the second time if it were only compared with itself. Why at least one: the
/// first reading after a gap (a dropout, a reconnect, the ride's start, a resume after the app was
/// killed) is exactly where a reacquisition spike lands, and with nothing before it there is
/// nothing to bound it. It is shown and kept as a sample, so the reading after it is judged
/// against it, but it can't become the max itself. What this can't catch: a spike that is the
/// first *two* readings after a gap, since its second is judged only against its first.
///
/// Why nothing is remembered between calls: a gate with its own baseline can latch, one rejected
/// reading leaving a stale baseline that rejects every honest one after it. Here each constraint
/// expires with its reading, so a rejection lasts at most `window`, and the gate needs no
/// persisted state to survive a resume.
enum MaxSpeedGate {
    /// The fastest a bicycle can gain speed: 4 m/s² (0.4 g).
    ///
    /// Two physical limits put it there. A bike pitches up over its rear axle once
    /// acceleration × centre-of-mass height exceeds g × the centre of mass's distance ahead of
    /// the rear contact patch: about 1.0–1.1 m and 0.4 m on a road bike, so 3.6–3.9 m/s². And
    /// power: a 1,500 W sprint peak moving 85 kg at 5 m/s is 3.5 m/s², falling as speed rises.
    /// In the eight rides of 2026-10-07 to 2026-11-03 (30,000 per-second track points of the
    /// displayed speed), the largest rise in one second was 3.9 m/s: a wheel sensor's first rate
    /// after a stop, which by `CSCCalculator`'s design spans about two seconds of pedalling. The
    /// most the gate allows in one second is 6.5 m/s.
    static let maxAccelerationMPS2 = 4.0

    /// Margin on top of the acceleration bound, for what the time between two readings doesn't
    /// capture.
    ///
    /// The gate measures the time between *displays*, but a reading measures speed over an
    /// earlier interval. `CSCCalculator`'s is the average over whole revolutions between the
    /// last-wheel-event times of two notifications, so it carries no revolution-counting error
    /// of its own. GPS speed is CoreLocation's filtered estimate. BLE and GPS delivery can bunch
    /// two readings closer together in time than the intervals they measured. A GPS reading is
    /// honestly off by up to its `speedAccuracy`, and at a fallback from the wheel sensor GPS
    /// differs from the wheel by its own noise plus the wheel's calibration error. 2.5 m/s is
    /// about 0.6 s of acceleration at the bound: generous, since no real one-second rise
    /// exceeded 4 m/s² alone (largest 3.9 m/s).
    static let readingSlackMPS = 2.5

    /// The widest GPS `speedAccuracy` whose speed may become the max.
    ///
    /// A judgement, not yet calibrated on device data: the rides on record don't store
    /// `speedAccuracy`. Set equal to `readingSlackMPS`, on the reasoning that a reading less
    /// certain than the gate's own margin can't meaningfully be held to the acceleration bound.
    /// Its own constant so widening the margin can't loosen this.
    static let maxGPSSpeedAccuracyMPS = 2.5

    /// How far back a reading is compared. A spike is rejected for up to this long; a reading
    /// held longer than this is sustained, not a spike, and physics can't tell it from a real
    /// one. As long as `SpeedFeature.staleDataWindow`, so a healthy wheel sensor's longest
    /// silence (4 s) never leaves a reading with nothing to be measured against.
    static let window: TimeInterval = 5

    /// The gate's answer for one reading, and which check refused it.
    enum Verdict: String, Equatable, Sendable {
        case admitted
        case untrustworthyGPSAccuracy = "gps speed accuracy"
        case noRecentReading = "no reading in the window to measure it against"
        case tooFast = "faster than a bicycle could have reached"
    }

    /// Whether `mps`, displayed now from `source`, may become the ride's max.
    ///
    /// - Parameters:
    ///   - speedAccuracy: the GPS fix's `speedAccuracy`, nil when CoreLocation marked it invalid.
    ///     Ignored for a wheel-sensor reading.
    ///   - samples: the displayed readings so far, oldest first (`SpeedFeature.speedSamples`).
    ///     Ones at `now` or later are ignored, which includes this reading's own.
    static func verdict(
        _ mps: Double,
        from source: SensorSource,
        speedAccuracy: Double?,
        at now: Date,
        after samples: [SpeedSample]
    ) -> Verdict {
        if source == .gps, !isTrustworthy(speedAccuracy: speedAccuracy) { return .untrustworthyGPSAccuracy }
        return reachability(mps, at: now, from: samples)
    }


    /// Whether a GPS speed with this accuracy is good enough to be a max.
    static func isTrustworthy(speedAccuracy: Double?) -> Bool {
        // An invalid accuracy is refused: #540's acceptance criteria. Counting it instead, and
        // leaving it to the acceleration bound, is this one `return`.
        guard let speedAccuracy, speedAccuracy >= 0 else { return false }
        return speedAccuracy <= maxGPSSpeedAccuracyMPS
    }

    /// Whether a bicycle could have reached `mps` by `now` from every reading of the last
    /// `window`, of which there must be at least one.
    static func isReachable(_ mps: Double, at now: Date, from samples: [SpeedSample]) -> Bool {
        reachability(mps, at: now, from: samples) == .admitted
    }

    private static func reachability(_ mps: Double, at now: Date, from samples: [SpeedSample]) -> Verdict {
        let cutoff = now.addingTimeInterval(-window)
        var hasReference = false
        for sample in samples.reversed() {
            guard sample.time >= cutoff else { break }
            let elapsed = now.timeIntervalSince(sample.time)
            guard elapsed > 0 else { continue }
            if mps > sample.mps + maxAccelerationMPS2 * elapsed + readingSlackMPS { return .tooFast }
            hasReference = true
        }
        return hasReference ? .admitted : .noRecentReading
    }
}
