import Foundation

// Shared logging helpers for the BLE clients. Lives beside them rather than in
// Models/ for the same reason BLEServiceUUIDs does: it is a cross-client concern
// of the transport layer, not part of the domain.

/// Admits at most one log line per bucket of the monotonic clock.
///
/// `.notice` is the only level `os_log` writes to the persisted store, so telemetry that has to
/// survive into a `log collect` archive has to live there — and a sensor notifying faster than
/// the bucket would flood it. Ride 2026-09-06 is the worked example: 4,275 radar frames at 8 Hz
/// filled 98.7% of a collected archive while every speed, cadence and HR sample, logged at
/// `.info`, evaporated (#212).
///
/// Buckets by whole multiples of `bucketSeconds` rather than measuring the interval since the
/// last admitted line. A nominally-1 Hz sensor whose packets jitter either side of a one-second
/// interval would be halved by an interval gate; bucketing lets every one through. It also makes
/// the gate immune to a clock that jumps in either direction — a changed bucket admits, whichever
/// way it moved.
///
/// Deliberately has no "always admit this one" escape hatch. An earlier draft bypassed the gate
/// whenever a sensor's emitted values changed shape, to be sure a rate dropping out was never the
/// sample the gate discarded. But `CSCCalculator.update` withholds a rate on five routine paths —
/// priming, a stopped counter below `zeroThreshold`, a zero time delta, re-priming after a stop,
/// and an over-cap spike — so the shape flips on every stop-and-go and the bound the gate exists
/// to provide would be gone. At 1 Hz a dropout is visible within a second anyway.
struct LogSampleGate {
    private let bucketSeconds: TimeInterval
    private var lastBucket: Int?

    init(bucketSeconds: TimeInterval = 1) {
        self.bucketSeconds = bucketSeconds
    }

    /// True at most once per bucket, and always on the first call.
    ///
    /// Pass `ProcessInfo.processInfo.systemUptime` for `uptime`. That is the *suspending*
    /// monotonic clock — it stops while the SoC sleeps, unlike the `ContinuousClock` these
    /// clients inject for their backoff ladders. The difference does not matter here and the
    /// error runs the safe way: the gate is only ever read from inside a BLE notification
    /// callback, which means the CPU is awake, and undercounting elapsed time can only make the
    /// gate more restrictive, never less. The log line's own timestamp comes from os_log's wall
    /// clock regardless.
    mutating func admit(uptime: TimeInterval) -> Bool {
        let bucket = Int((uptime / bucketSeconds).rounded(.down))
        guard bucket != lastBucket else { return false }
        lastBucket = bucket
        return true
    }
}

extension Data {
    /// Space-separated uppercase hex, the form every raw-frame log line in the BLE clients uses.
    ///
    /// Call this *inside* the log interpolation, never into a `let` above it. `OSLogMessage`
    /// takes its arguments as `@autoclosure @escaping` and `osLogInternal` runs its
    /// `isEnabled` check before invoking them, so an interpolated call costs nothing at a
    /// disabled level — while a hoisted `let` runs on every notification whatever the level.
    /// That hoist is what put a hex string on the CoreBluetooth callback path 8 times a
    /// second in `VariaRadarClient` (#212).
    var loggableHex: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
