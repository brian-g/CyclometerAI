import Charts
import SwiftUI

// MARK: - W2 Average Speed Widget

/// W2 — Average Speed 1×1, per `W2 - Avg Speed (1x1)` in Design.sketch: the ride average over a
/// watermark of recent speed, with the average's own history drawn across it — green while it
/// climbs, amber while it falls (#140).
struct AverageSpeedWidget: View {
    let averageSpeed: Double            // m/s; 0 → no moving time yet → "—"
    let speedHistory: [SpeedSample]     // the speed watermark
    let averageHistory: [SpeedSample]   // `averageSpeed` over the same window
    var unit: UnitSystem = .metric

    var body: some View {
        ZStack {
            if !speedHistory.isEmpty || !averageHistory.isEmpty {
                AverageSpeedHistoryChart(speedHistory: speedHistory, averageHistory: averageHistory, unit: unit)
                    // A line at the top of the range strokes past the frame — at a steady speed the
                    // average is the range's top — and Charts doesn't clip, so it drew over the cell above.
                    .clipped()
            }
            VStack(alignment: .leading, spacing: 0) {
                WidgetLabel("Average Speed")
                HeroNumber(displayAverage, unit: hasAverage ? unit.speedLabel : "").heroNumberSize(.medium)
                Spacer()
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cyBgSecondary)
        .widgetDetail(label: AverageSpeedDashboardWidget.title, value: accessibilityValue) {
            RideMetricsSheet()
        }
    }

    /// Zero until the ride has a moving second — an average of nothing, not a slow ride.
    private var hasAverage: Bool { averageSpeed > 0 }

    private var displayAverage: String {
        hasAverage ? unit.speed(fromMPS: averageSpeed).formatted(.number.precision(.fractionLength(1))) : "—"
    }

    /// What VoiceOver reads after the title (#361), with no "—" read aloud.
    var accessibilityValue: String {
        hasAverage ? unit.spokenSpeed(fromMPS: averageSpeed) : "No reading"
    }
}

// MARK: - Average Trend

/// W2's average line, split into runs that each only rise or only fall so each run takes one
/// color. Neighbouring runs share their junction sample, so the line stays unbroken. A level
/// stretch continues the run before it; the first run takes the first change's direction.
enum AverageSpeedTrend {
    struct Run: Equatable {
        let isRising: Bool
        let samples: [SpeedSample]
    }

    static func runs(_ samples: [SpeedSample]) -> [Run] {
        guard samples.count > 1 else { return [] }
        let pairs = zip(samples, samples.dropFirst())
        var isRising = pairs.first { $0.mps != $1.mps }.map { $0.mps < $1.mps } ?? true
        var runs: [Run] = []
        var current = [samples[0]]
        for (previous, sample) in pairs {
            let direction = sample.mps == previous.mps ? isRising : previous.mps < sample.mps
            if direction != isRising {
                runs.append(Run(isRising: isRising, samples: current))
                current = [previous]
                isRising = direction
            }
            current.append(sample)
        }
        runs.append(Run(isRising: isRising, samples: current))
        return runs
    }
}

// MARK: - History Chart

private struct AverageSpeedHistoryChart: View {
    let speedHistory: [SpeedSample]
    let averageHistory: [SpeedSample]
    let unit: UnitSystem

    var body: some View {
        Chart {
            ForEach(Array(speedHistory.enumerated()), id: \.offset) { _, sample in
                AreaMark(
                    x: .value("t", sample.time),
                    y: .value("speed", unit.speed(fromMPS: sample.mps))
                )
                .foregroundStyle(Color.cyTextTertiary.opacity(Opacity.watermark))
            }
            ForEach(Array(AverageSpeedTrend.runs(averageHistory).enumerated()), id: \.offset) { index, run in
                ForEach(Array(run.samples.enumerated()), id: \.offset) { _, sample in
                    LineMark(
                        x: .value("t", sample.time),
                        y: .value("speed", unit.speed(fromMPS: sample.mps)),
                        series: .value("run", index)
                    )
                    .foregroundStyle(run.isRising ? Color.cyRatingGood : Color.cyRatingOkay)
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}

// MARK: - Previews

/// A ride that speeds up, then fades: the average climbs, then falls (#140).
private let previewHistory: (speed: [SpeedSample], average: [SpeedSample]) = {
    let start = Date(timeIntervalSinceReferenceDate: 0)
    let speed = (0..<60).map { i in
        let mps = i < 40 ? 4 + Double(i) * 0.15 : 10 - Double(i - 40) * 0.3
        return SpeedSample(time: start.addingTimeInterval(Double(i) * 60), mps: mps)
    }
    var total = 0.0
    let average = speed.enumerated().map { i, sample in
        total += sample.mps
        return SpeedSample(time: sample.time, mps: total / Double(i + 1))
    }
    return (speed, average)
}()

#Preview("Metric") {
    AverageSpeedWidget(
        averageSpeed: 5.6,
        speedHistory: previewHistory.speed,
        averageHistory: previewHistory.average,
        unit: .metric
    )
    .frame(width: 196, height: 96)
}

#Preview("Imperial — Dark") {
    AverageSpeedWidget(
        averageSpeed: 5.6,
        speedHistory: previewHistory.speed,
        averageHistory: previewHistory.average,
        unit: .imperial
    )
    .frame(width: 196, height: 96)
    .preferredColorScheme(.dark)
}

#Preview("No moving time") {
    AverageSpeedWidget(averageSpeed: 0, speedHistory: [], averageHistory: [])
        .frame(width: 196, height: 96)
}
