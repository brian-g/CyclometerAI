import Foundation

/// A reading on a time axis, as the dashboard's watermarks and the sheets' charts plot it (#399).
protocol TimedSample {
    var time: Date { get }
    var value: Double { get }
    init(time: Date, value: Double)
}

extension Array {
    /// At most `resolution` contiguous slices, in order, together holding every element once.
    ///
    /// Integer edges: `Double(count) / resolution` scaled back up can land one short of `count`
    /// (e.g. 123 at 60) and drop the newest sample (#140 review).
    func buckets(to resolution: Int) -> [ArraySlice<Element>] {
        let buckets = Swift.min(count, resolution)
        return (0..<buckets).map { i in self[(i * count / buckets)..<((i + 1) * count / buckets)] }
    }
}

extension Collection where Element: TimedSample {
    /// The mean time and value of these samples; nil when there are none.
    var mean: Element? {
        guard !isEmpty else { return nil }
        let n = Double(count)
        let time = reduce(0) { $0 + $1.time.timeIntervalSinceReferenceDate } / n
        return Element(time: Date(timeIntervalSinceReferenceDate: time), value: reduce(0) { $0 + $1.value } / n)
    }
}

extension Array where Element: TimedSample {
    /// At most `resolution` samples, each the mean time and value of a contiguous bucket — so a
    /// downsampled series still sits on the time axis it was recorded on (W2 plots two series
    /// against one axis, #140). Returned unchanged when already within `resolution`.
    func bucketAveraged(to resolution: Int) -> [Element] {
        guard count > resolution else { return self }
        return buckets(to: resolution).compactMap(\.mean)
    }
}
