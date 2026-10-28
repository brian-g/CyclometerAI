import Foundation

/// A single timestamped, valid altitude reading (metres) kept for the sheets' elevation charts and
/// W17's watermark. Never built from an invalid fix (#303).
struct AltitudeSample: Equatable, Sendable {
    let time: Date
    let meters: Double
}

extension AltitudeSample: TimedSample {
    var value: Double { meters }
    init(time: Date, value: Double) { self.init(time: time, meters: value) }
}
