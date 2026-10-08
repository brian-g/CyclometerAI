import SwiftUI

// MARK: - Ride Metrics

/// One row's value: as shown, and as VoiceOver reads it — units and times in words, and "No
/// reading" for "—" (UX.md §Widget Details, #361).
struct MetricReading: Equatable {
    let shown: String
    let spoken: String

    static let missing = MetricReading(shown: "—", spoken: "No reading")
}

/// What UX.md's "Sheet: Ride metrics" shows (#144): display strings for its rows, and the
/// histories behind its charts. Every row reads "—" until it has a source; distance and the two
/// times are real at zero.
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

    private var hasAverage: Bool { averageSpeedMPS > 0 }

    var currentSpeed: MetricReading { speedMPS.map(speed) ?? .missing }
    var averageSpeed: MetricReading { hasAverage ? speed(averageSpeedMPS) : .missing }
    var maxSpeed: MetricReading { maxSpeedMPS > 0 ? speed(maxSpeedMPS) : .missing }

    var currentPace: MetricReading { speedMPS.flatMap(pace) ?? .missing }
    var averagePace: MetricReading { (hasAverage ? pace(averageSpeedMPS) : nil) ?? .missing }

    var distance: MetricReading {
        MetricReading(
            shown: "\(oneDecimal(unit.distance(fromMeters: distanceMeters))) \(unit.distanceLabel)",
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
        MetricReading(shown: "\(oneDecimal(unit.speed(fromMPS: mps))) \(unit.speedLabel)", spoken: unit.spokenSpeed(fromMPS: mps))
    }

    private func pace(_ mps: Double) -> MetricReading? {
        guard let shown = unit.formattedPace(fromMPS: mps), let spoken = unit.spokenPace(fromMPS: mps) else { return nil }
        return MetricReading(shown: "\(shown) \(unit.paceLabel)", spoken: spoken)
    }

    private func time(_ seconds: Int) -> MetricReading {
        MetricReading(shown: seconds.formattedElapsed, spoken: seconds.spokenElapsed)
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
struct RideMetricsSheet: View {
    var metrics = RideMetrics()

    @Environment(\.dismiss) private var dismiss
    @State private var detent = PresentationDetent.medium

    var body: some View {
        NavigationStack {
            RideMetricsList(metrics: metrics)
                .navigationTitle("Ride Metrics")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .close) { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large], selection: $detent)
    }
}

/// The sheet's charts and rows, apart from its navigation chrome so a snapshot can pin them.
struct RideMetricsList: View {
    let metrics: RideMetrics

    private static let chartHeight: CGFloat = 140
    private static let donutHeight: CGFloat = 120

    var body: some View {
        let range = metrics.historyRange
        // A one-bucket run is a single point, which a line can't draw.
        let paceRuns = PaceTrace.runs(metrics.speedHistory, resolution: RideMetricsCharts.maxPlottedPoints)
            .filter { $0.count > 1 }
        List {
            Section("Speed") {
                if let range {
                    RideSpeedChart(
                        speedSamples: metrics.speedHistory,
                        altitudeSamples: metrics.altitudeHistory,
                        range: range,
                        unit: metrics.unit
                    )
                    .frame(height: Self.chartHeight)
                }
                row("Current", metrics.currentSpeed)
                row("Average", metrics.averageSpeed)
                row("Max", metrics.maxSpeed)
            }
            Section("Pace") {
                if let range, !paceRuns.isEmpty {
                    RidePaceChart(runs: paceRuns, range: range, unit: metrics.unit)
                        .frame(height: Self.chartHeight)
                }
                row("Current", metrics.currentPace)
                row("Average", metrics.averagePace)
            }
            Section {
                row("Distance", metrics.distance)
            }
            Section("Time") {
                if metrics.rideSeconds > 0 {
                    DonutChart(slices: [
                        DonutSlice(id: "moving", value: TimeInterval(metrics.movingSeconds), color: .cyPrimary),
                        DonutSlice(id: "stopped", value: TimeInterval(metrics.stoppedSeconds), color: .cyTextTertiary)
                    ])
                    .frame(height: Self.donutHeight)
                    .frame(maxWidth: .infinity)
                }
                row("Moving Time", metrics.movingTime)
                row("Ride Time", metrics.rideTime)
            }
        }
    }

    private func row(_ label: String, _ reading: MetricReading) -> some View {
        LabeledContent(label, value: reading.shown)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(reading.spoken)
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
    RideMetricsSheet(metrics: .sample())
}

#Preview("Imperial — Dark") {
    RideMetricsSheet(metrics: .sample(.imperial))
    .preferredColorScheme(.dark)
}

#Preview("No data") {
    RideMetricsSheet()
}
