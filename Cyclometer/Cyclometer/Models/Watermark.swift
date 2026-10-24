import Foundation

/// A point on a dashboard watermark: one time bucket's mean time and value, and which unbroken run of
/// readings it belongs to — the chart draws each run as its own series, so the line breaks between them.
struct WatermarkPoint: Equatable, Sendable {
    let time: Date
    let value: Double
    let run: Int
}

/// The time axis behind the dashboard's watermarks: W1 Speed, W4 Heart Rate, W5 Cadence and W17/W18
/// Elevation.
///
/// They used to plot each series by sample index, each downsampled by count, so a series that went
/// quiet was squeezed together. On a ride where the cadence sensor slept through a 15-minute stop while
/// speed carried on from GPS, W1 drew the stop and W5 didn't, and the two traces no longer lined up.
/// Plotted against time over one window they share, they line up, and a silence shows as a break.
enum Watermark {
    /// Time buckets across the window: a minute each over a full hour.
    static let bucketCount = 60

    /// A silence longer than this breaks the line instead of being drawn across. Longer than any
    /// healthy source goes quiet — HealthKit heart rate lands in batches seconds apart, and a CSC
    /// sensor's longest silence is a few seconds — and shorter than a stop with the sensors asleep.
    static let gapSeconds: TimeInterval = 120

    /// The window every watermark plots over: from the oldest reading in any series to the newest,
    /// but never longer than `span`. The clamp is not redundant with each series' own trimming — a
    /// series only trims when it gains a reading, so a sensor gone quiet keeps readings older than
    /// `span`, and they would stretch everyone's axis. Nil when there are no readings at all.
    static func window(oldest: [Date?], newest: [Date?], span: TimeInterval) -> ClosedRange<Date>? {
        guard let end = newest.compactMap({ $0 }).max(), let start = oldest.compactMap({ $0 }).min()
        else { return nil }
        return max(start, end.addingTimeInterval(-span))...end
    }

    /// `samples`, oldest first, as the means of `bucketCount` equal slices of `window` — keyed by run
    /// as well as by bucket, so no point averages across a gap. Each point keeps its bucket's mean
    /// time rather than the bucket's middle, so it sits where its readings were. Samples outside
    /// `window` are left out.
    static func points<Sample>(
        _ samples: [Sample],
        over window: ClosedRange<Date>,
        time: (Sample) -> Date,
        value: (Sample) -> Double
    ) -> [WatermarkPoint] {
        let width = window.upperBound.timeIntervalSince(window.lowerBound) / Double(bucketCount)
        var points: [WatermarkPoint] = []
        var run = 0
        var bucket: Int?
        var previous: Date?
        var timeSum = 0.0
        var valueSum = 0.0
        var count = 0.0

        func closeBucket() {
            guard count > 0 else { return }
            points.append(WatermarkPoint(
                time: Date(timeIntervalSinceReferenceDate: timeSum / count),
                value: valueSum / count,
                run: run
            ))
            timeSum = 0
            valueSum = 0
            count = 0
        }

        for sample in samples {
            let t = time(sample)
            guard window.contains(t) else { continue }
            // A window of one instant has no width to divide; all of it is the one bucket.
            let index = width > 0 ? min(Int(t.timeIntervalSince(window.lowerBound) / width), bucketCount - 1) : 0
            if let previous, t.timeIntervalSince(previous) > gapSeconds {
                closeBucket()
                run += 1
            } else if index != bucket {
                closeBucket()
            }
            bucket = index
            previous = t
            timeSum += t.timeIntervalSinceReferenceDate
            valueSum += value(sample)
            count += 1
        }
        closeBucket()
        return points
    }
}

extension Array where Element == WatermarkPoint {
    /// The x-domain a watermark chart plots over: the shared window when there is one, otherwise these
    /// points' own span. Never zero-wide — a lone reading, or none, still gives zone bands a width to
    /// fill (#79).
    func plotDomain(_ window: ClosedRange<Date>?) -> ClosedRange<Date> {
        let range = window
            ?? first.map { $0.time...Swift.max($0.time, last?.time ?? $0.time) }
            ?? Date(timeIntervalSinceReferenceDate: 0)...Date(timeIntervalSinceReferenceDate: 0)
        return range.lowerBound < range.upperBound ? range : range.lowerBound...range.lowerBound.addingTimeInterval(1)
    }
}
