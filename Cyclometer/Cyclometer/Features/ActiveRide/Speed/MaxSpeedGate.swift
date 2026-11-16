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
///   accuracy is invalid, or wider than `readingSlackMPS`, never counts. The simulator's
///   simulated location (`simctl location`) reports a valid speed with `speedAccuracy` −1, so a
///   GPS-only ride there never sets a max.
/// - **A bicycle can only speed up so fast.** A reading must be reachable from every displayed
///   reading of the last `window`: no more than `maxAccelerationMPS2` per second above it, plus
///   `readingSlackMPS`. This is the only check a wheel sensor gets, since CSC has no accuracy
///   field. `CSCCalculator` already drops a zero event-time delta, re-primes after a stop and on
///   a reconnect, and caps a reading at 15 rev/s, but 15 rev/s is still ~113 km/h.
///
/// Why "every reading of the window" rather than "the previous reading": a spike that lasts two
/// seconds would pass the second time if it were only compared with itself. Why nothing is
/// remembered between calls: a gate with its own baseline can latch, one rejected reading leaving
/// a stale baseline that rejects every honest one after it. Here each constraint expires with
/// its reading, so a rejection lasts at most `window`, and the gate needs no persisted state to
/// survive a resume. With no displayed reading in the window (the ride's first reading, the first
/// after a resume or a gap of `window` or more) a reading is unconstrained, and only GPS's
/// accuracy check applies to it.
enum MaxSpeedGate {
    /// The fastest a bicycle can gain speed: 4 m/s² (0.4 g).
    ///
    /// Two physical limits put it there. A bike pitches up over its rear axle once
    /// acceleration × centre-of-mass height exceeds g × the centre of mass's distance ahead of
    /// the rear contact patch: about 1.0–1.1 m and 0.4 m on a road bike, so 3.6–3.9 m/s². And
    /// power: a 1,500 W sprint peak moving 85 kg at 5 m/s is 3.5 m/s², falling as speed rises.
    /// In the eight rides of 2026-10-07 to 2026-11-03 (28,000 per-second track points of the
    /// displayed speed), the largest rise in one second was 3.9 m/s: a wheel sensor's first rate
    /// after a stop, which by `CSCCalculator`'s design spans about two seconds of pedalling. The
    /// most the gate allows in one second is 6.5 m/s.
    static let maxAccelerationMPS2 = 4.0

    /// How far an honest reading may stand above the truth, for either source.
    ///
    /// A wheel sensor counts whole revolutions, so one landing in the neighbouring second moves
    /// that second's reading by a revolution per second: 2.1 m/s on a 700c wheel, 2.35 m/s on a
    /// 29 × 2.4 in. The 2026-10-16 descent has a 2.1 m/s one-second dip at 14 m/s. GPS is held to
    /// the same figure through its `speedAccuracy`: a reading less certain than this can't be
    /// held to the acceleration bound at all.
    static let readingSlackMPS = 2.5

    /// How far back a reading is compared. A spike is rejected for up to this long; a reading
    /// held longer than this is sustained, not a spike, and physics can't tell it from a real
    /// one. As long as `SpeedFeature.staleDataWindow`, so a healthy wheel sensor's longest
    /// silence (4 s) never leaves a reading unconstrained.
    static let window: TimeInterval = 5

    /// Whether `mps`, displayed now from `source`, may become the ride's max.
    ///
    /// - Parameters:
    ///   - speedAccuracy: the GPS fix's `speedAccuracy`, nil when CoreLocation marked it invalid.
    ///     Ignored for a wheel-sensor reading.
    ///   - samples: the displayed readings so far, oldest first (`SpeedFeature.speedSamples`).
    ///     Ones at `now` or later are ignored, which includes this reading's own.
    static func admits(
        _ mps: Double,
        from source: SensorSource,
        speedAccuracy: Double?,
        at now: Date,
        after samples: [SpeedSample]
    ) -> Bool {
        (source != .gps || isTrustworthy(speedAccuracy: speedAccuracy))
            && isReachable(mps, at: now, from: samples)
    }

    /// Whether a GPS speed with this accuracy is good enough to be a max.
    static func isTrustworthy(speedAccuracy: Double?) -> Bool {
        guard let speedAccuracy else { return false }
        return speedAccuracy >= 0 && speedAccuracy <= readingSlackMPS
    }

    /// Whether a bicycle could have reached `mps` by `now` from every reading of the last `window`.
    static func isReachable(_ mps: Double, at now: Date, from samples: [SpeedSample]) -> Bool {
        let cutoff = now.addingTimeInterval(-window)
        for sample in samples.reversed() {
            guard sample.time >= cutoff else { break }
            let elapsed = now.timeIntervalSince(sample.time)
            guard elapsed > 0 else { continue }
            if mps > sample.mps + maxAccelerationMPS2 * elapsed + readingSlackMPS { return false }
        }
        return true
    }
}
