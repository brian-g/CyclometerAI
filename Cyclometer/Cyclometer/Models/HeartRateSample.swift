import Foundation

/// A single timestamped heart-rate reading (bpm), for W4's watermark and trend and the Heart Rate
/// sheet's chart (#145).
struct HeartRateSample: Equatable, Sendable {
    let time: Date
    let bpm: Int
}

/// Which way heart rate is heading: W4's ▲/▼ (Design.sketch "W4 - Heart Rate", #145).
///
/// The last `recentSeconds` of readings against the `recentSeconds…baselineSeconds` before them,
/// counted back from the newest reading rather than the clock, so it needs no `now`. Means, not
/// the newest reading alone, so one noisy beat doesn't flip the arrow. A window with no reading —
/// a sparse Apple Watch, or a ride a few seconds old — is steady: no evidence of a change.
enum HeartRateTrend: Equatable, Sendable {
    case up, steady, down

    static let recentSeconds: TimeInterval = 10
    static let baselineSeconds: TimeInterval = 30
    /// The smallest change of mean that counts. Below it, a strap's beat-to-beat wander would
    /// flicker the arrow.
    static let thresholdBPM = 3.0

    init(_ samples: [HeartRateSample]) {
        guard let newest = samples.last?.time else { self = .steady; return }
        func mean(from older: TimeInterval, to newer: TimeInterval) -> Double? {
            let bpms = samples.lazy
                .filter { newest.timeIntervalSince($0.time) < older && newest.timeIntervalSince($0.time) >= newer }
                .map { Double($0.bpm) }
            let count = bpms.count
            return count > 0 ? bpms.reduce(0, +) / Double(count) : nil
        }
        guard let recent = mean(from: Self.recentSeconds, to: 0),
              let baseline = mean(from: Self.baselineSeconds, to: Self.recentSeconds)
        else { self = .steady; return }
        let change = recent - baseline
        self = change >= Self.thresholdBPM ? .up : change <= -Self.thresholdBPM ? .down : .steady
    }
}
