import Foundation
@testable import Cyclometer

/// The stop that auto-pause slept through, from the ride of 2026-09-20 10:45 EDT
/// (`Cyclometer_2026-09-20_10-45.gpx`, #262).
///
/// 15:07:00Z–15:13:02Z: the rider comes to a halt, waits, shuffles forward twice, and
/// finally gives up and taps Pause by hand at 15:13:02 — which is where the track's
/// 26-minute gap begins. Auto-pause was on, with a 10-second threshold, and never fired
/// once in those six minutes.
///
/// Recorded as plain values rather than a bundled capture file, the same way
/// `GPSFixReplayFixtures` and `RadarPassFixtures` are, so the data stays readable and
/// diffable in review.
///
/// **Two things the export cost this data, both of which matter when reading a test
/// against it.**
///
/// *Rounding.* `GPXExporter` writes `<gpxtpx:speed>` to one decimal, so every `0.0` below
/// was really a raw 0.02–0.04 m/s — CoreLocation's stationary noise floor, and exactly
/// what the old `speedMPS == 0` test could not see. Read literally the series is kinder
/// to that old rule than the hardware was, and it still defeats it: the 0.1–0.8 readings
/// scattered through the stop reset the counter often enough that ten consecutive exact
/// zeros never accumulate. `AutoPauseThresholdTests` pins the unrounded noise floor
/// directly; what this fixture adds is the aggregate question — whether
/// `stationarySpeedMPS`/`movingSpeedMPS` pause a real stop promptly without chattering,
/// and without pausing a rider who is still moving.
///
/// *Gaps.* `GPSFixFilter` suppressed 43 of these 363 seconds, and the exporter drops a
/// point that carried no speed, so the file is not evenly spaced. The series below is
/// per-second with the last reported speed carried forward across those gaps, which is
/// what `SpeedFeature.State.speedMPS` itself does — it holds its value until a new sample
/// replaces it.
enum AutoPauseReplayFixtures {
    /// Reported speed in m/s, one entry per second from 15:07:00Z to 15:13:02Z inclusive.
    static let stopWindowSpeedsMPS: [Double] = [
        3.0, 3.0, 3.0, 2.8, 2.6, 2.2, 2.1, 1.9, 1.4, 0.8, 0.1, 0.3,
        0.3, 0.1, 0.0, 0.4, 0.2, 0.0, 0.2, 0.2, 0.1, 0.3, 0.3, 0.3,
        0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.8, 0.8, 0.8, 0.8, 0.8,
        0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3,
        0.3, 0.3, 0.3, 0.3, 0.3, 0.0, 0.0, 0.0, 0.1, 0.1, 0.1, 0.0,
        0.1, 0.1, 0.1, 0.1, 0.0, 0.0, 0.2, 0.1, 0.1, 0.0, 0.1, 0.1,
        0.0, 0.0, 0.1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.2, 0.1, 0.2, 0.2,
        0.1, 0.2, 0.1, 0.0, 0.4, 0.3, 0.0, 0.1, 0.2, 0.2, 0.1, 0.1,
        0.4, 0.3, 0.1, 0.4, 0.2, 0.2, 0.1, 0.0, 0.1, 0.0, 0.0, 0.0,
        0.0, 0.0, 0.1, 0.2, 0.1, 0.1, 0.1, 0.1, 0.0, 0.0, 0.0, 0.0,
        0.0, 0.1, 0.1, 0.2, 0.0, 0.1, 0.1, 0.0, 0.2, 0.1, 0.1, 0.2,
        0.2, 0.5, 0.0, 0.1, 0.0, 0.1, 0.1, 0.0, 0.0, 0.0, 0.0, 0.1,
        0.0, 0.1, 0.0, 0.1, 0.1, 0.0, 0.1, 0.0, 0.0, 0.0, 0.0, 0.0,
        0.0, 0.0, 0.0, 0.0, 0.1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        0.0, 0.0, 0.0, 0.0, 0.1, 0.0, 0.2, 0.2, 0.1, 0.1, 0.1, 0.1,
        0.4, 0.3, 0.8, 0.5, 0.3, 0.0, 0.1, 0.1, 0.1, 0.1, 0.1, 0.0,
        0.0, 0.2, 0.1, 1.1, 1.0, 0.8, 0.4, 0.4, 0.2, 0.3, 0.1, 0.0,
        0.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.1, 0.2,
        0.0, 0.1, 0.2, 0.1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        0.0, 0.0, 0.0, 0.0, 0.0, 0.1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        0.3, 0.1, 0.2, 0.0, 0.2, 0.2, 0.1, 0.3, 0.2, 0.1, 0.0, 0.1,
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.1, 0.2,
        0.0, 0.1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        0.2, 0.2, 0.0, 0.0, 0.1, 0.2, 0.2, 0.2, 0.0, 0.1, 0.5, 0.3,
        0.2, 0.2, 1.2, 3.0, 2.7, 1.8, 1.5, 0.8, 1.2, 1.1, 1.1, 1.3,
        1.3, 1.2, 1.1, 0.9, 0.5, 0.2, 0.2, 0.0, 0.0, 0.2, 0.1, 0.2,
        0.0, 0.0, 0.0, 0.1, 0.1, 0.3, 0.1, 0.1, 0.1, 0.3, 0.1, 0.1,
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.2, 0.1, 0.0, 0.1, 0.0, 0.1,
        0.1, 0.0, 0.0
    ]
}
