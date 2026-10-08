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
    /// The Ride Metrics sheet's data. A closure so the card never reads it; only the open sheet does (#144).
    var metrics: () -> RideMetrics = { RideMetrics() }

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
                averageHero.heroNumberSize(.medium)
                Spacer()
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cyBgSecondary)
        .widgetDetail(label: AverageSpeedDashboardWidget.title, value: accessibilityValue) {
            RideMetricsSheet(metrics: metrics())
        }
    }

    /// Zero until the ride has a moving second — an average of nothing, not a slow ride.
    private var hasAverage: Bool { averageSpeed > 0 }

    private var averageHero: HeroNumber<EmptyView> {
        hasAverage ? HeroNumber(unit.speed(fromMPS: averageSpeed), unit: unit.speedLabel) : HeroNumber("—", unit: "")
    }

    /// What VoiceOver reads after the title (#361), with no "—" read aloud.
    var accessibilityValue: String {
        hasAverage ? unit.spokenSpeed(fromMPS: averageSpeed) : "No reading"
    }
}

// MARK: - Average Trend

/// W2's average line, split into runs that each rise or fall, so each run takes one color.
/// Neighbouring runs share their turning sample, so the line stays unbroken.
///
/// A run turns only once the average has come back more than `turnThresholdMPS` from the run's
/// peak (or trough). Comparing each step on its own sign flickered: late in a ride the average
/// barely moves, and bucket means re-cut every second wobble around it (#140 review). Measured
/// from the extreme, a slow real decline still adds up past the threshold and turns the line.
enum AverageSpeedTrend {
    struct Run: Equatable {
        let isRising: Bool
        let samples: [SpeedSample]
    }

    /// One step of W2's number (0.1 km/h). A move the number can't show isn't a trend. Taken in
    /// canonical m/s, so the line turns at the same point in either unit.
    static let turnThresholdMPS = Measurement(value: 0.1, unit: UnitSpeed.kilometersPerHour)
        .converted(to: .metersPerSecond).value

    static func runs(_ samples: [SpeedSample]) -> [Run] {
        guard samples.count > 1 else { return [] }
        var runs: [Run] = []
        var runStart = 0
        var extreme = 0
        // Unknown until the average first moves a full threshold away from where it started.
        var isRising: Bool?
        for (i, sample) in samples.enumerated().dropFirst() {
            guard let rising = isRising else {
                if abs(sample.mps - samples[0].mps) > turnThresholdMPS {
                    isRising = sample.mps > samples[0].mps
                    extreme = i
                }
                continue
            }
            let fromExtreme = sample.mps - samples[extreme].mps
            if rising ? fromExtreme >= 0 : fromExtreme <= 0 {
                extreme = i
            } else if abs(fromExtreme) > turnThresholdMPS {
                runs.append(Run(isRising: rising, samples: Array(samples[runStart...extreme])))
                runStart = extreme
                extreme = i
                isRising = !rising
            }
        }
        runs.append(Run(isRising: isRising ?? true, samples: Array(samples[runStart...])))
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

#Preview("Metric") {
    AverageSpeedWidget(
        averageSpeed: SpeedSample.sampleHourAverage.last!.mps,
        speedHistory: SpeedSample.sampleHour,
        averageHistory: SpeedSample.sampleHourAverage,
        unit: .metric
    )
    .frame(width: 196, height: 96)
}

#Preview("Imperial — Dark") {
    AverageSpeedWidget(
        averageSpeed: SpeedSample.sampleHourAverage.last!.mps,
        speedHistory: SpeedSample.sampleHour,
        averageHistory: SpeedSample.sampleHourAverage,
        unit: .imperial
    )
    .frame(width: 196, height: 96)
    .preferredColorScheme(.dark)
}

#Preview("No moving time") {
    AverageSpeedWidget(averageSpeed: 0, speedHistory: [], averageHistory: [])
        .frame(width: 196, height: 96)
}
