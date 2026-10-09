import Charts
import SwiftUI

// MARK: - Heart Rate

/// What UX.md's "Sheet: Heart rate" shows (#145): the reading W4 and W12 show, and the rider's
/// zones with the ride's time in each.
struct HeartRateMetrics: Equatable {
    /// `displayHeartRateBPM`; 0 → no reading.
    var bpm: Int = 0
    /// `displayHRZone`, 1–5; 0 → no reading.
    var zone: Int = 0
    var source: HRSource = .none
    /// Each zone's bpm range, zone 1 first, as S12's table shows them.
    var zoneBounds: [ClosedRange<Int>] = HeartRateZone.allCases.map { RiderProfile().bounds(for: $0) }
    /// Recorded seconds in each zone, zone 1 first, as S10 will count them.
    var zoneSeconds: [Int] = []
    /// The last hour of readings, behind the chart (`State.hrSamples`).
    var history: [HeartRateSample] = []
    /// Elevation over the same window, beneath the chart, as on the Cadence sheet.
    var altitudeHistory: [AltitudeSample] = []

    /// One row of the zone table.
    struct ZoneRow: Equatable, Identifiable {
        let zone: Int
        let name: String
        let range: MetricReading
        /// The donut's slice; `time` is the same seconds as text.
        let seconds: Int
        let time: MetricReading
        var id: Int { zone }
    }

    var current: MetricReading {
        if source == .none { return MetricReading(shown: "No HR Source", spoken: "No HR source") }
        guard bpm > 0 else { return .missing }
        return MetricReading(shown: "\(bpm) bpm", spoken: "\(bpm) beats per minute")
    }

    var currentZone: MetricReading {
        guard source != .none, let zone = HeartRateZone(rawValue: zone) else { return .missing }
        return MetricReading(
            shown: "Z\(zone.rawValue) \(zone.s12DisplayName)",
            spoken: "Zone \(zone.rawValue), \(zone.s12DisplayName)"
        )
    }

    var hasZoneTime: Bool { zoneSeconds.contains { $0 > 0 } }

    /// The chart's span, first reading to last. `nil` with nothing to plot.
    var historyRange: ClosedRange<Date>? {
        guard let first = history.first?.time, let last = history.last?.time, first < last else { return nil }
        return first...last
    }

    var zoneRows: [ZoneRow] {
        zip(HeartRateZone.allCases, zoneBounds).map { zone, bounds in
            let seconds = zone.rawValue <= zoneSeconds.count ? zoneSeconds[zone.rawValue - 1] : 0
            return ZoneRow(
                zone: zone.rawValue,
                name: "Z\(zone.rawValue) \(zone.s12DisplayName)",
                range: MetricReading(
                    shown: "\(bounds.lowerBound)–\(bounds.upperBound) bpm",
                    spoken: "\(bounds.lowerBound) to \(bounds.upperBound) beats per minute"
                ),
                seconds: seconds,
                time: MetricReading(
                    shown: Duration.seconds(seconds).formatted(.time(pattern: .hourMinuteSecond(padHourToLength: 1))),
                    spoken: seconds.spokenElapsed
                )
            )
        }
    }
}

extension ActiveRideFeature.State {
    /// The Heart Rate sheet's inputs: the fields W4 and W12 read, and the histories behind its chart.
    var heartRateMetrics: HeartRateMetrics {
        HeartRateMetrics(
            bpm: displayHeartRateBPM,
            zone: displayHRZone,
            source: hrSource,
            zoneBounds: hrZoneBounds,
            zoneSeconds: hrZoneSeconds,
            history: hrSamples,
            altitudeHistory: altitudeSamples
        )
    }
}

// MARK: - Heart Rate Sheet

/// UX.md's "Sheet: Heart rate", shared by W4 Heart Rate and W12 Zones (#145).
///
/// `metrics` is called in this view's own `body`, not the presenter's `.sheet` builder, so the
/// open sheet follows the ride (see `RideMetricsSheet`, #144).
struct HeartRateSheet: View {
    var metrics: () -> HeartRateMetrics = { HeartRateMetrics() }

    @Environment(\.dismiss) private var dismiss
    @State private var detent = PresentationDetent.medium

    var body: some View {
        let metrics = metrics()
        NavigationStack {
            HeartRateList(metrics: metrics)
                .navigationTitle("Heart Rate")
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

/// The sheet's rows, apart from its navigation chrome so a snapshot can pin them.
struct HeartRateList: View {
    let metrics: HeartRateMetrics

    private static let chartHeight: CGFloat = 140
    private static let donutHeight: CGFloat = 120

    var body: some View {
        let zoneRows = metrics.zoneRows
        List {
            Section {
                if let range = metrics.historyRange {
                    HeartRateChart(
                        history: metrics.history,
                        altitudeHistory: metrics.altitudeHistory,
                        zoneBounds: metrics.zoneBounds,
                        range: range
                    )
                        .frame(height: Self.chartHeight)
                }
                row("Heart Rate", metrics.current)
                LabeledContent("Zone") {
                    HStack(spacing: Spacing.sm) {
                        if metrics.currentZone != .missing {
                            zoneDot(metrics.zone)
                        }
                        Text(metrics.currentZone.shown)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Zone")
                .accessibilityValue(metrics.currentZone.spoken)
            }
            Section("Time in Zones") {
                if metrics.hasZoneTime {
                    DonutChart(slices: zoneRows.map {
                        DonutSlice(id: "\($0.zone)", value: TimeInterval($0.seconds), color: .hrZone($0.zone))
                    })
                    .frame(height: Self.donutHeight)
                    .frame(maxWidth: .infinity)
                }
                ForEach(zoneRows) { zoneRow($0) }
            }
        }
    }

    private func row(_ label: String, _ reading: MetricReading) -> some View {
        LabeledContent(label, value: reading.shown)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(reading.spoken)
    }

    private func zoneRow(_ zone: HeartRateMetrics.ZoneRow) -> some View {
        HStack(spacing: Spacing.sm) {
            zoneDot(zone.zone)
            VStack(alignment: .leading, spacing: 0) {
                Text(zone.name)
                Text(zone.range.shown)
                    .font(.footnote)
                    .foregroundStyle(Color.cyTextSecondary)
            }
            Spacer(minLength: Spacing.sm)
            Text(zone.time.shown)
                .monospacedDigit()
                .foregroundStyle(Color.cyTextSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(zone.name)
        .accessibilityValue("\(zone.range.spoken), \(zone.time.spoken)")
    }

    private func zoneDot(_ zone: Int) -> some View {
        Circle()
            .fill(Color.hrZone(zone))
            .frame(width: Spacing.sm, height: Spacing.sm)
    }
}

// MARK: - Heart Rate Chart

/// `CadenceDetailChart` for heart rate (#145): the last hour on the rider's zone bands, with the
/// ride's elevation as a faint watermark behind, on the Ride Metrics time axis — whose whole-minute
/// ticks don't repeat a label, as the Cadence chart's automatic ones do.
struct HeartRateChart: View {
    let history: [HeartRateSample]
    let altitudeHistory: [AltitudeSample]
    /// Zone 1 first, as `HeartRateMetrics.zoneBounds`.
    let zoneBounds: [ClosedRange<Int>]
    let range: ClosedRange<Date>

    /// Elevation is normalised into the heart-rate y-domain (a chart has one y-scale), filling only
    /// the lower part of it so it never competes with the trace. Cadence's constants.
    private static let elevationHeightFraction = 0.6
    private static let minElevationSpanMeters = RouteGeometry.elevationNoiseThresholdMeters

    private struct Point: Identifiable {
        let time: Date
        let value: Double
        var id: Date { time }
    }

    /// At most `RideMetricsCharts.maxPlottedPoints` bucket means (integer edges, as
    /// `bucketAveraged(to:)`): an hour of 1 Hz readings would be thousands of marks.
    private static func downsampled(_ points: [Point]) -> [Point] {
        let count = points.count
        let buckets = min(count, RideMetricsCharts.maxPlottedPoints)
        return (0..<buckets).map { i in
            let slice = points[(i * count / buckets)..<((i + 1) * count / buckets)]
            let n = Double(slice.count)
            return Point(
                time: Date(timeIntervalSinceReferenceDate: slice.reduce(0) { $0 + $1.time.timeIntervalSinceReferenceDate } / n),
                value: slice.reduce(0) { $0 + $1.value } / n
            )
        }
    }

    var body: some View {
        let heartRate = Self.downsampled(history.map { Point(time: $0.time, value: Double($0.bpm)) })
        let domain = zoneBounds.chartDomain(including: heartRate.map(\.value))
        let elevation = elevationPoints(base: domain.lowerBound,
                                        height: (domain.upperBound - domain.lowerBound) * Self.elevationHeightFraction)
        Chart {
            HeartRateZoneBands(zoneBounds: zoneBounds, domain: domain, x: range)
            ForEach(elevation) { point in
                AreaMark(
                    x: .value("t", point.time),
                    yStart: .value("base", domain.lowerBound),
                    yEnd: .value("elevation", point.value),
                    series: .value("Series", "elevation")
                )
                .foregroundStyle(Color.cyTextPrimary.opacity(Opacity.watermark))
            }
            ForEach(heartRate) { point in
                LineMark(
                    x: .value("t", point.time),
                    y: .value("bpm", point.value),
                    series: .value("Series", "heartRate")
                )
                .foregroundStyle(Color.cyTextPrimary)
            }
        }
        .chartYScale(domain: domain)
        .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
        .modifier(RideTimeAxis(range: range))
    }

    /// Elevation over `range` as heights from `base` up to `base + height`.
    private func elevationPoints(base: Double, height: Double) -> [Point] {
        let visible = altitudeHistory.filter { range.contains($0.time) }
        guard let low = visible.map(\.meters).min(), let high = visible.map(\.meters).max() else { return [] }
        let span = max(high - low, Self.minElevationSpanMeters)
        return Self.downsampled(visible.map {
            Point(time: $0.time, value: base + ($0.meters - low) / span * height)
        })
    }
}

// MARK: - Previews

extension HeartRateMetrics {
    /// A strap reading 156 bpm in zone 3 (151–163), 39 minutes in, against the default profile:
    /// one reading every 5 s, warming up, rolling between Z2 and Z4, easing at a stop at 17 min,
    /// over the climb and descent of `RideMetrics.sample`.
    static let sample = HeartRateMetrics(
        bpm: 156,
        zone: 3,
        source: .bleStrap,
        zoneSeconds: [312, 846, 702, 318, 42],
        history: (0..<468).map { i in
            let warmUp = min(Double(i) / 60, 1)
            let effort = (204..<228).contains(i) ? 128 : 150 + 14 * sin(Double(i) / 18)
            return HeartRateSample(
                time: Date(timeIntervalSince1970: 1_000_000).addingTimeInterval(Double(i) * 5),
                bpm: Int(100 + (effort - 100) * warmUp)
            )
        },
        altitudeHistory: RideMetrics.sample().altitudeHistory
    )
}

#Preview("Live") {
    HeartRateSheet { .sample }
}

#Preview("Live — Dark") {
    HeartRateSheet { .sample }
        .preferredColorScheme(.dark)
}

#Preview("No HR source") {
    HeartRateSheet()
}
