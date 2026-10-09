import Charts
import SwiftUI

// MARK: - Pace Trace

/// W11's pace over the speed history, as runs of moving time (#144). A bucket with no moving
/// sample is a gap, not a pace: at a standstill pace runs to infinity.
enum PaceTrace {
    /// The speed samples in at most `resolution` buckets, each the mean of its moving samples —
    /// above `ActiveRideFeature.stationarySpeedMPS`, the threshold that stops the ride's clock
    /// and odometer. Mean speed, inverted later, is the pace over the bucket's moving time.
    /// Consecutive moving buckets form one run.
    static func runs(_ samples: [SpeedSample], resolution: Int) -> [[SpeedSample]] {
        let count = samples.count
        let buckets = min(count, resolution)
        var runs: [[SpeedSample]] = []
        var run: [SpeedSample] = []
        for i in 0..<buckets {
            // Integer edges, as `bucketAveraged(to:)`.
            let moving = samples[(i * count / buckets)..<((i + 1) * count / buckets)]
                .filter { $0.mps > ActiveRideFeature.stationarySpeedMPS }
            guard !moving.isEmpty else {
                if !run.isEmpty { runs.append(run) }
                run = []
                continue
            }
            let n = Double(moving.count)
            let time = moving.reduce(0) { $0 + $1.time.timeIntervalSinceReferenceDate } / n
            run.append(SpeedSample(
                time: Date(timeIntervalSinceReferenceDate: time),
                mps: moving.reduce(0) { $0 + $1.mps } / n
            ))
        }
        if !run.isEmpty { runs.append(run) }
        return runs
    }

    /// Steps, in seconds, a pace axis may tick at.
    private static let tickStepsSeconds: [Double] = [15, 30, 60, 120, 300, 600]
    private static let maxTicks = 4
    /// How far past the median pace the axis reaches. A bucket that only just cleared the
    /// stopped threshold — rolling up to a light — is a pace many times the riding one; left in
    /// the domain it would squash the riding pace into a sliver. Slower than this is clipped.
    private static let slowestPaceOverMedian = 2.0

    /// The pace axis for `runs`, in seconds: fastest pace to the slowest, capped at twice the
    /// median, widened to whole multiples of the smallest step that gives at most four ticks.
    static func axis(_ runs: [[SpeedSample]], unit: UnitSystem) -> (domain: ClosedRange<Double>, ticks: [Double])? {
        let paces = runs.joined().compactMap { unit.paceSeconds(fromMPS: $0.mps) }.sorted()
        guard let fastest = paces.first, let slowest = paces.last else { return nil }
        let slow = min(slowest, paces[paces.count / 2] * slowestPaceOverMedian)
        let step = tickStepsSeconds.first {
            ceil(slow / $0) - floor(fastest / $0) < Double(maxTicks)
        } ?? tickStepsSeconds[tickStepsSeconds.count - 1]
        let lower = floor(fastest / step) * step
        let upper = max(ceil(slow / step) * step, lower + step)
        return (lower...upper, Array(stride(from: lower, through: upper, by: step)))
    }
}

// MARK: - Shared

enum RideMetricsCharts {
    /// Marks plotted per series. A cap, not a target: a short ride has fewer.
    static let maxPlottedPoints = 120

    /// Minute steps a time axis may tick at.
    private static let tickStepsMinutes: [Double] = [1, 2, 5, 10, 15, 20, 30, 60]
    private static let maxTicks = 3

    /// Clock-time ticks across `range`: at most three, on whole multiples of the smallest step
    /// that fits, in `timeZone`. The axis labels to the minute, so ticks closer than a minute
    /// would repeat a label — what automatic ticks did a minute into a ride. A span that crosses
    /// no whole minute (history restarts with the app) is labelled at its start.
    static func timeTicks(in range: ClosedRange<Date>, timeZone: TimeZone) -> [Date] {
        let spanMinutes = range.upperBound.timeIntervalSince(range.lowerBound) / 60
        // Fewer than `maxTicks` steps across the span: a span of exactly three steps that starts
        // on one would tick four times.
        let step = 60 * (tickStepsMinutes.first { spanMinutes / $0 < Double(maxTicks) } ?? 60)
        let offset = Double(timeZone.secondsFromGMT(for: range.lowerBound))
        let first = ((range.lowerBound.timeIntervalSinceReferenceDate + offset) / step).rounded(.up) * step - offset
        let ticks = stride(from: first, through: range.upperBound.timeIntervalSinceReferenceDate, by: step)
            .map { Date(timeIntervalSinceReferenceDate: $0) }
        return ticks.isEmpty ? [range.lowerBound] : ticks
    }
}

/// One time axis for both charts, so the pace chart lines up under the speed chart. Shared with
/// the Heart Rate sheet's chart (#145).
struct RideTimeAxis: ViewModifier {
    let range: ClosedRange<Date>

    @Environment(\.timeZone) private var timeZone
    @Environment(\.locale) private var locale

    func body(content: Content) -> some View {
        content
            .chartXScale(domain: range)
            .chartXAxis {
                AxisMarks(values: RideMetricsCharts.timeTicks(in: range, timeZone: timeZone)) {
                    AxisGridLine()
                    // In the environment's zone and locale, as the ticks are: the default style
                    // formats in the device's.
                    AxisValueLabel(format: Date.FormatStyle(locale: locale, timeZone: timeZone).hour().minute())
                }
            }
            .chartLegend(.hidden)
    }
}

// MARK: - Speed Chart

/// Speed over the history window, with the ride's elevation as a faint area beneath — the
/// Cadence sheet's treatment (#144).
struct RideSpeedChart: View {
    let speedSamples: [SpeedSample]
    let altitudeSamples: [AltitudeSample]
    let range: ClosedRange<Date>
    let unit: UnitSystem

    /// Elevation is scaled into the speed y-domain (a chart has one y-scale), filling only the
    /// lower part of it so it never competes with the speed line.
    private static let elevationHeightFraction = 0.6
    /// Smallest elevation span stretched to full height. Below it (GPS noise on a flat ride) the
    /// profile stays flat rather than amplifying jitter.
    private static let minElevationSpanMeters = RouteGeometry.elevationNoiseThresholdMeters

    private struct Point: Identifiable {
        let time: Date
        let value: Double
        var id: Date { time }
    }

    private var speedPoints: [Point] {
        speedSamples.bucketAveraged(to: RideMetricsCharts.maxPlottedPoints).map {
            Point(time: $0.time, value: unit.speed(fromMPS: $0.mps))
        }
    }

    /// Elevation over `range`, as heights from 0 to `top`, in at most
    /// `RideMetricsCharts.maxPlottedPoints` bucket means (integer edges, as `bucketAveraged(to:)`).
    private func elevationPoints(top: Double) -> [Point] {
        let visible = altitudeSamples.filter { range.contains($0.time) }
        guard let low = visible.map(\.meters).min(), let high = visible.map(\.meters).max() else { return [] }
        let span = max(high - low, Self.minElevationSpanMeters)
        let points = visible.map { Point(time: $0.time, value: ($0.meters - low) / span * top) }
        let resolution = RideMetricsCharts.maxPlottedPoints
        guard points.count > resolution else { return points }
        return (0..<resolution).map { i in
            let slice = points[(i * points.count / resolution)..<((i + 1) * points.count / resolution)]
            let n = Double(slice.count)
            return Point(
                time: Date(timeIntervalSinceReferenceDate: slice.reduce(0) { $0 + $1.time.timeIntervalSinceReferenceDate } / n),
                value: slice.reduce(0) { $0 + $1.value } / n
            )
        }
    }

    var body: some View {
        let speed = speedPoints
        let elevation = elevationPoints(top: (speed.map(\.value).max() ?? 0) * Self.elevationHeightFraction)
        Chart {
            ForEach(elevation) { point in
                AreaMark(
                    x: .value("t", point.time),
                    yStart: .value("base", 0),
                    yEnd: .value("elevation", point.value),
                    series: .value("Series", "elevation")
                )
                .foregroundStyle(Color.cyTextPrimary.opacity(Opacity.watermark))
            }
            ForEach(speed) { point in
                LineMark(
                    x: .value("t", point.time),
                    y: .value("speed", point.value),
                    series: .value("Series", "speed")
                )
                .foregroundStyle(Color.cyPrimary)
            }
        }
        .modifier(RideTimeAxis(range: range))
    }
}

// MARK: - Pace Chart

/// Pace over the history window, faster higher so it reads like the speed chart above it, with
/// a gap wherever the rider stopped (#144).
///
/// Plotted as negative seconds: an explicit domain can't be reversed, and negating it puts the
/// faster (smaller) pace on top. The labels negate back.
struct RidePaceChart: View {
    /// From `PaceTrace.runs`: every sample is moving, so each has a pace.
    let runs: [[SpeedSample]]
    let range: ClosedRange<Date>
    let unit: UnitSystem

    var body: some View {
        if let axis = PaceTrace.axis(runs, unit: unit) {
            Chart {
                ForEach(Array(runs.enumerated()), id: \.offset) { index, run in
                    ForEach(run, id: \.time) { sample in
                        if let pace = unit.paceSeconds(fromMPS: sample.mps) {
                            LineMark(
                                x: .value("t", sample.time),
                                y: .value("pace", -pace),
                                series: .value("run", index)
                            )
                            .foregroundStyle(Color.cyPrimary)
                        }
                    }
                }
            }
            .chartYScale(domain: -axis.domain.upperBound ... -axis.domain.lowerBound)
            .chartYAxis {
                AxisMarks(values: axis.ticks.map { -$0 }) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let negated = value.as(Double.self) {
                            Text(Duration.seconds(-negated).formatted(.time(pattern: .minuteSecond)))
                        }
                    }
                }
            }
            // A pace past the axis's slow end (see `PaceTrace.axis`) runs off the plot, not over
            // the labels.
            .chartPlotStyle { $0.clipped() }
            .modifier(RideTimeAxis(range: range))
        }
    }
}
