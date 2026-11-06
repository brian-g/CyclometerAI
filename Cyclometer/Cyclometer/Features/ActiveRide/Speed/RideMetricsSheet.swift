import SwiftUI

// MARK: - Ride Metrics

/// What UX.md's "Sheet: Ride metrics" shows (#144): its readings, and the histories behind its
/// charts. Every reading is "—" until it has a source; distance and the two times are real at zero.
struct RideMetrics: Equatable {
    var speedMPS: Double? = nil      // displayed speed; nil → no source
    var averageSpeedMPS: Double = 0  // 0 → no moving second yet
    var maxSpeedMPS: Double = 0
    var distanceMeters: Double = 0
    /// W3's Duration: seconds moving, so `averageSpeedMPS` × this = distance.
    var movingSeconds: Int = 0
    /// W1's Time: recording seconds, stopped ones included.
    var rideSeconds: Int = 0
    var unit: UnitSystem = .metric
    /// The last `SpeedFeature.historyWindow` of displayed speed, behind the speed and pace charts.
    var speedHistory: [SpeedSample] = []
    /// Elevation over the same window, beneath the speed chart.
    var altitudeHistory: [AltitudeSample] = []
    /// S15's per-mile or per-km splits (#547). Empty on the live sheet, which shows none.
    var paceSplits: [PaceSplit] = []

    private var hasAverage: Bool { averageSpeedMPS > 0 }

    var currentSpeed: MetricReading { speedMPS.map(speed) ?? .missing }
    var averageSpeed: MetricReading { hasAverage ? speed(averageSpeedMPS) : .missing }
    var maxSpeed: MetricReading { maxSpeedMPS > 0 ? speed(maxSpeedMPS) : .missing }

    var currentPace: MetricReading { speedMPS.flatMap(pace) ?? .missing }
    var averagePace: MetricReading { (hasAverage ? pace(averageSpeedMPS) : nil) ?? .missing }

    var distance: MetricReading {
        MetricReading(
            value: oneDecimal(unit.distance(fromMeters: distanceMeters)),
            unit: unit.distanceLabel,
            spoken: unit.spokenDistance(fromMeters: distanceMeters)
        )
    }
    var movingTime: MetricReading { time(movingSeconds) }
    var rideTime: MetricReading { time(rideSeconds) }
    /// Ride Time not spent moving: stops short of auto-pause. Paused time is in neither.
    var stoppedSeconds: Int { max(rideSeconds - movingSeconds, 0) }

    /// The span the charts share: the speed history's, so the pace chart lines up beneath the
    /// speed chart even when the rider was stopped at either end. `nil` with nothing to plot.
    var historyRange: ClosedRange<Date>? {
        guard let first = speedHistory.first?.time, let last = speedHistory.last?.time, first < last else { return nil }
        return first...last
    }

    private func speed(_ mps: Double) -> MetricReading {
        MetricReading(value: oneDecimal(unit.speed(fromMPS: mps)), unit: unit.speedLabel, spoken: unit.spokenSpeed(fromMPS: mps))
    }

    private func pace(_ mps: Double) -> MetricReading? {
        guard let shown = unit.formattedPace(fromMPS: mps), let spoken = unit.spokenPace(fromMPS: mps) else { return nil }
        return MetricReading(value: shown, unit: unit.paceLabel, spoken: spoken)
    }

    private func time(_ seconds: Int) -> MetricReading {
        MetricReading(value: seconds.formattedElapsed, spoken: seconds.spokenElapsed)
    }

    private func oneDecimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}

extension ActiveRideFeature.State {
    /// The Ride Metrics sheet's inputs, from the same fields the dashboard widgets read.
    var rideMetrics: RideMetrics {
        RideMetrics(
            speedMPS: speed.speedMPS,
            averageSpeedMPS: averageSpeedMPS,
            maxSpeedMPS: maxSpeedMPS,
            distanceMeters: distanceMeters,
            movingSeconds: speedSampleCount,
            rideSeconds: elapsedSeconds,
            unit: unitSystem,
            speedHistory: speed.speedSamples,
            altitudeHistory: altitudeSamples
        )
    }
}

// MARK: - Ride Metrics Sheet

/// UX.md's "Sheet: Ride metrics", shared by W1 Speed, W2 Avg Speed, W3 Duration, W6 Distance and
/// W11 Pace (#144). W5 Cadence is tagged the same in UX.md but keeps its own sheet (#147).
///
/// `metrics` is called in this view's own `body`, so the ride state it reads invalidates the
/// sheet directly. Called in the presenter's `.sheet` builder instead, a change re-ran the
/// builder but now and then never reached the open sheet, which stayed stale until the card
/// behind it redrew — and W3's card doesn't while the rider is stopped.
struct RideMetricsSheet: View {
    var metrics: () -> RideMetrics = { RideMetrics() }

    @State private var detent = PresentationDetent.medium

    var body: some View {
        let metrics = metrics()
        NavigationStack {
            RideMetricsList(metrics: metrics)
                .navigationTitle("Ride Metrics")
                .navigationBarTitleDisplayMode(.inline)
                .sheetCloseButton()
        }
        .presentationDetents([.medium, .large], selection: $detent)
    }
}

/// The sheet's charts and readings, apart from its navigation chrome so a snapshot can pin them.
struct RideMetricsList: View {
    let metrics: RideMetrics

    var body: some View {
        List {
            Section {
                ReadingColumns { ReadingColumn("Distance", metrics.distance) }
            }
            RideSpeedSection(metrics: metrics)
            RidePaceSection(metrics: metrics)
            RideTimeSection(metrics: metrics)
        }
    }
}

/// The sheet's sections one by one, shared with S15, which shows them over the whole ride without
/// the current readings (#536).
enum RideMetricsSections {
    static let chartHeight: CGFloat = 140
    static let donutHeight: CGFloat = 120
}

struct RideSpeedSection: View {
    let metrics: RideMetrics
    var showsCurrent = true

    var body: some View {
        Section("Speed") {
            if let range = metrics.historyRange {
                RideSpeedChart(
                    speedSamples: metrics.speedHistory,
                    altitudeSamples: metrics.altitudeHistory,
                    range: range,
                    unit: metrics.unit
                )
                .frame(height: RideMetricsSections.chartHeight)
            }
            ReadingColumns {
                if showsCurrent { ReadingColumn("Current", metrics.currentSpeed) }
                ReadingColumn("Average", metrics.averageSpeed)
                ReadingColumn("Max", metrics.maxSpeed)
            }
        }
    }
}

struct RidePaceSection: View {
    let metrics: RideMetrics
    var showsCurrent = true

    var body: some View {
        // A one-bucket run is a single point, which a line can't draw.
        let paceRuns = PaceTrace.runs(metrics.speedHistory, resolution: RideMetricsCharts.maxPlottedPoints)
            .filter { $0.count > 1 }
        Section("Pace") {
            if let range = metrics.historyRange, !paceRuns.isEmpty {
                RidePaceChart(runs: paceRuns, range: range, unit: metrics.unit)
                    .frame(height: RideMetricsSections.chartHeight)
            }
            ReadingColumns {
                if showsCurrent { ReadingColumn("Current", metrics.currentPace) }
                ReadingColumn("Average", metrics.averagePace)
            }
            if !metrics.paceSplits.isEmpty {
                PaceSplitRows(splits: metrics.paceSplits, unit: metrics.unit)
            }
        }
    }
}

struct RideTimeSection: View {
    let metrics: RideMetrics

    var body: some View {
        Section("Time") {
            if metrics.rideSeconds > 0 {
                DonutChart(slices: [
                    DonutSlice(id: "moving", value: TimeInterval(metrics.movingSeconds), color: .cyPrimary),
                    DonutSlice(id: "stopped", value: TimeInterval(metrics.stoppedSeconds), color: .cyTextTertiary)
                ])
                .frame(height: RideMetricsSections.donutHeight)
                .frame(maxWidth: .infinity)
            }
            ReadingColumns {
                ReadingColumn("Moving Time", metrics.movingTime)
                ReadingColumn("Ride Time", metrics.rideTime)
            }
        }
    }
}

// MARK: - Previews

extension RideMetrics {
    /// A 39-minute ride with two minutes stopped, averaging ~20 km/h: one reading every 5 s,
    /// speed rolling between ~18 and ~32 km/h, a stop at 17 min, over a climb and a descent.
    static func sample(_ unit: UnitSystem = .metric) -> RideMetrics {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let readings = 0..<468
        return RideMetrics(
            speedMPS: 7.89,
            averageSpeedMPS: 12_300 / 2_220,
            maxSpeedMPS: 9.47,
            distanceMeters: 12_300,
            movingSeconds: 2_220,
            rideSeconds: 2_340,
            unit: unit,
            speedHistory: readings.map { i in
                let mps = (204..<228).contains(i) ? 0 : 7 + 2 * sin(Double(i) / 20)
                return SpeedSample(time: start.addingTimeInterval(Double(i) * 5), mps: mps)
            },
            altitudeHistory: readings.map { i in
                AltitudeSample(time: start.addingTimeInterval(Double(i) * 5), meters: 120 + 40 * sin(Double(i) / 150))
            }
        )
    }
}

#Preview("Live") {
    RideMetricsSheet { .sample() }
}

#Preview("Imperial — Dark") {
    RideMetricsSheet { .sample(.imperial) }
    .preferredColorScheme(.dark)
}

#Preview("No data") {
    RideMetricsSheet()
}
