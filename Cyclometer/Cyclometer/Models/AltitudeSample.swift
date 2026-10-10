import Foundation

/// A single timestamped, valid altitude reading (metres) kept for the sheets' elevation charts and
/// W17's watermark. Never built from an invalid fix (#303).
struct AltitudeSample: Equatable, Sendable {
    let time: Date
    let meters: Double
}

extension Array where Element == AltitudeSample {
    /// At most `resolution` samples, each the mean time and altitude of a contiguous bucket —
    /// `SpeedSample`'s `bucketAveraged(to:)`, for elevation (#387). Unchanged when already within it.
    func bucketAveraged(to resolution: Int) -> [AltitudeSample] {
        guard count > resolution else { return self }
        return (0..<resolution).map { i in
            let slice = self[(i * count / resolution)..<((i + 1) * count / resolution)]
            let n = Double(slice.count)
            let time = slice.reduce(0) { $0 + $1.time.timeIntervalSinceReferenceDate } / n
            return AltitudeSample(
                time: Date(timeIntervalSinceReferenceDate: time),
                meters: slice.reduce(0) { $0 + $1.meters } / n
            )
        }
    }
}
