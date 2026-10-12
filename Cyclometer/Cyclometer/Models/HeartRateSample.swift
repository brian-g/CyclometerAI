import Foundation

/// A single timestamped heart-rate reading (bpm), for W4's watermark and trend and the Heart Rate
/// sheet's chart (#145).
struct HeartRateSample: Equatable, Sendable {
    let time: Date
    let bpm: Int
}

/// Which way heart rate is heading: W4's ▲/▼ (#145).
extension Trend {
    static let heartRateRecentSeconds: TimeInterval = 10
    static let heartRateBaselineSeconds: TimeInterval = 30
    /// The smallest change of mean that counts. Below it, a strap's beat-to-beat wander would
    /// flicker the arrow.
    static let heartRateThresholdBPM = 3.0

    /// The last `heartRateRecentSeconds` of readings against the
    /// `heartRateRecentSeconds…heartRateBaselineSeconds` before them, counted back from the newest
    /// reading rather than the clock, so it needs no `now`. Means, not the newest reading alone, so
    /// one noisy beat doesn't flip the arrow. A window with no reading — a sparse Apple Watch, or a
    /// ride a few seconds old — is steady: no evidence of a change.
    init(_ samples: [HeartRateSample]) {
        guard let newest = samples.last?.time else { self = .steady; return }
        func mean(from older: TimeInterval, to newer: TimeInterval) -> Double? {
            let bpms = samples.lazy
                .filter { newest.timeIntervalSince($0.time) < older && newest.timeIntervalSince($0.time) >= newer }
                .map { Double($0.bpm) }
            let count = bpms.count
            return count > 0 ? bpms.reduce(0, +) / Double(count) : nil
        }
        guard let recent = mean(from: Self.heartRateRecentSeconds, to: 0),
              let baseline = mean(from: Self.heartRateBaselineSeconds, to: Self.heartRateRecentSeconds)
        else { self = .steady; return }
        let change = recent - baseline
        self = change >= Self.heartRateThresholdBPM ? .up : change <= -Self.heartRateThresholdBPM ? .down : .steady
    }
}
