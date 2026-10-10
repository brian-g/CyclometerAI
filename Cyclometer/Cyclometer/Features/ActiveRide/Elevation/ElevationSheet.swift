import Charts
import SwiftUI

// MARK: - Elevation

/// What the Elevation sheet shows (#387): the readings W14–W18 show, the ride's range and steepest
/// grades, its elevation over time, and the route's profile when there is one.
struct ElevationMetrics: Equatable {
    var altitudeMeters: Double? = nil
    var ascentMeters: Double = 0
    var descentMeters: Double = 0
    var highestMeters: Double? = nil
    var lowestMeters: Double? = nil
    var gradePercent: Double? = nil
    var steepestClimbPercent: Double? = nil
    var steepestDescentPercent: Double? = nil
    /// The last hour of `altitudeSamples`, behind the chart.
    var history: [AltitudeSample] = []
    /// `NavigationRoute.elevationProfile`, and how far along it the rider is.
    var routeProfile: [Double]? = nil
    var routeProgress: Double? = nil
    var unit: UnitSystem = .metric

    var current: MetricReading { elevation(altitudeMeters) }
    var ascent: MetricReading { elevation(ascentMeters) }
    var descent: MetricReading { elevation(descentMeters) }
    var highest: MetricReading { elevation(highestMeters) }
    var lowest: MetricReading { elevation(lowestMeters) }
    var grade: MetricReading { gradeReading(gradePercent) }
    var steepestClimb: MetricReading { gradeReading(steepestClimbPercent) }
    var steepestDescent: MetricReading { gradeReading(steepestDescentPercent) }

    /// The chart's span, first sample to last. `nil` with nothing to plot.
    var historyRange: ClosedRange<Date>? {
        guard let first = history.first?.time, let last = history.last?.time, first < last else { return nil }
        return first...last
    }

    private func elevation(_ meters: Double?) -> MetricReading {
        guard let meters else { return .missing }
        let value = unit.elevation(fromMeters: meters).formatted(.number.precision(.fractionLength(0)))
        return MetricReading(shown: "\(value) \(unit.elevationLabel)", spoken: unit.spokenElevation(fromMeters: meters))
    }

    private func gradeReading(_ percent: Double?) -> MetricReading {
        guard percent != nil else { return .missing }
        return MetricReading(shown: "\(Grade.value(percent))\(Grade.unit)", spoken: Grade.spoken(percent))
    }
}

extension ActiveRideFeature.State {
    /// W17's and W18's watermark: `altitudeSamples` in at most `SpeedFeature.watermarkResolution`
    /// bucket means — Speed's axis.
    var altitudeWatermarkSamples: [Double] {
        altitudeSamples.bucketAveraged(to: SpeedFeature.watermarkResolution).map(\.meters)
    }

    /// The Elevation sheet's inputs: the fields W14–W18 read, and the histories behind its charts.
    var elevationMetrics: ElevationMetrics {
        let profile = navigation.activeRoute?.elevationProfile
        return ElevationMetrics(
            altitudeMeters: altitude,
            ascentMeters: elevation.ascentMeters,
            descentMeters: elevation.descentMeters,
            highestMeters: elevation.highestMeters,
            lowestMeters: elevation.lowestMeters,
            gradePercent: elevation.gradePercent,
            steepestClimbPercent: elevation.steepestClimbPercent,
            steepestDescentPercent: elevation.steepestDescentPercent,
            history: altitudeSamples,
            routeProfile: profile,
            routeProgress: profile == nil ? nil : navigation.routeProgressFraction,
            unit: unitSystem
        )
    }
}

// MARK: - Elevation Sheet

/// The Elevation sheet, shared by W14–W18 (#387).
///
/// `metrics` is called in this view's own `body`, not the presenter's `.sheet` builder, so the
/// open sheet follows the ride (see `RideMetricsSheet`, #144).
struct ElevationSheet: View {
    var metrics: () -> ElevationMetrics = { ElevationMetrics() }

    @Environment(\.dismiss) private var dismiss
    @State private var detent = PresentationDetent.medium

    var body: some View {
        let metrics = metrics()
        NavigationStack {
            ElevationList(metrics: metrics)
                .navigationTitle("Elevation")
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
struct ElevationList: View {
    let metrics: ElevationMetrics

    private static let chartHeight: CGFloat = 140

    var body: some View {
        List {
            Section {
                if let range = metrics.historyRange {
                    ElevationChart(history: metrics.history, range: range, unit: metrics.unit)
                        .frame(height: Self.chartHeight)
                }
                row("Current", metrics.current)
                row("Highest", metrics.highest)
                row("Lowest", metrics.lowest)
            }
            Section("Climbing") {
                row("Ascent", metrics.ascent)
                row("Descent", metrics.descent)
            }
            Section("Grade") {
                row("Current", metrics.grade)
                row("Steepest Climb", metrics.steepestClimb)
                row("Steepest Descent", metrics.steepestDescent)
            }
            if let profile = metrics.routeProfile {
                Section("Route") {
                    RouteProfileChart(profile: profile, progress: metrics.routeProgress)
                        .frame(height: Self.chartHeight)
                        .accessibilityLabel("Route elevation profile")
                }
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

// MARK: - Elevation Chart

/// The ride's elevation over the history window, on the Ride Metrics time axis.
private struct ElevationChart: View {
    let history: [AltitudeSample]
    let range: ClosedRange<Date>
    let unit: UnitSystem

    private struct Point: Identifiable {
        let time: Date
        let value: Double
        var id: Date { time }
    }

    var body: some View {
        let points = history
            .bucketAveraged(to: RideMetricsCharts.maxPlottedPoints)
            .map { Point(time: $0.time, value: unit.elevation(fromMeters: $0.meters)) }
        let meters = history.map(\.meters).elevationChartDomain
        let domain = unit.elevation(fromMeters: meters.lowerBound)...unit.elevation(fromMeters: meters.upperBound)
        Chart(points) { point in
            AreaMark(
                x: .value("t", point.time),
                yStart: .value("base", domain.lowerBound),
                yEnd: .value("elevation", point.value)
            )
            .foregroundStyle(Color.cyPrimary.opacity(Opacity.watermark))
            LineMark(x: .value("t", point.time), y: .value("elevation", point.value))
                .foregroundStyle(Color.cyPrimary)
        }
        .chartYScale(domain: domain)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let elevation = value.as(Double.self) {
                        Text("\(elevation.formatted(.number.precision(.fractionLength(0)))) \(unit.elevationLabel)")
                    }
                }
            }
        }
        .modifier(RideTimeAxis(range: range))
        .accessibilityLabel("Elevation over time")
    }
}

// MARK: - Previews

extension AltitudeSample {
    /// A sample hour, one reading a minute: a climb of about 60 m, a descent, and a roller — so
    /// the previews and S08's elevation entries draw a profile.
    static let sampleHour: [AltitudeSample] = (0..<60).map { minute in
        let t = Double(minute)
        return AltitudeSample(time: Date(timeIntervalSinceReferenceDate: t * 60),
                              meters: 250 + 30 * sin(t / 10) + 6 * sin(t / 3) + t / 2)
    }
}

extension ElevationMetrics {
    /// Mid-ride on `AltitudeSample.sampleHour`, 40% of the way along a route over the same ground.
    static func sample(_ unit: UnitSystem = .metric) -> ElevationMetrics {
        ElevationMetrics(
            altitudeMeters: 284,
            ascentMeters: 412,
            descentMeters: 368,
            highestMeters: 312,
            lowestMeters: 221,
            gradePercent: 4.4,
            steepestClimbPercent: 9.2,
            steepestDescentPercent: -7.6,
            history: AltitudeSample.sampleHour,
            routeProfile: AltitudeSample.sampleHour.map(\.meters),
            routeProgress: 0.4,
            unit: unit
        )
    }
}

#Preview("Elevation sheet") {
    ElevationList(metrics: .sample())
}
