import Charts
import SwiftUI

// MARK: - W4 Heart Rate / W12 HR Zones

/// Shared empty state for W4/W12 when neither BLE nor HealthKit has a reading (#161).
private struct NoHRSourceLabel: View {
    var body: some View {
        Text("No HR Source")
            .font(.caption)
            .foregroundStyle(.cyTextTertiary)
    }
}

/// W4 — Heart Rate, 1×1 and 2×1. Built as W5 Cadence is (#145): the last hour as a watermark on
/// the rider's zone bands behind the number, and Avg/Max at 2×1. The ▲/▼ is the trend, from
/// Design.sketch "W4 - Heart Rate".
struct HeartRateWidget: View {
    /// `ActiveRideFeature.State.displayHeartRateBPM`, not the raw reading — it resolves
    /// a brief strap silence to the held value rather than to `0` (#221). `0` here means
    /// "no reading", which a connected strap does report: `—` is the honest answer, and
    /// distinct from `source == .none`'s "nothing is paired at all".
    let bpm: Int
    let zone: Int
    let source: HRSource
    /// bpm for the watermark, oldest first (`State.hrWatermarkSamples`).
    var history: [Double] = []
    /// Zone 1 first (`State.hrZoneBounds`): the watermark's bands.
    var zoneBounds: [ClosedRange<Int>] = HeartRateMetrics().zoneBounds
    var trend: HeartRateTrend = .steady
    /// 0 → no recorded reading yet.
    var averageBPM: Int = 0
    var maxBPM: Int = 0
    var size: WidgetSize = .oneByOne
    /// The Heart Rate sheet's data. A closure so the card never reads it; only the open sheet
    /// does, in its own body (#145).
    var metrics: () -> HeartRateMetrics = { HeartRateMetrics() }

    /// The trend triangle's size, from Design.sketch "W4 - Heart Rate" (20 × 18).
    private static let trendSize: CGFloat = 18

    var body: some View {
        ZStack {
            if !history.isEmpty {
                HeartRateHistoryChart(history: history, zoneBounds: zoneBounds)
            }
            VStack(alignment: .leading, spacing: 0) {
                WidgetLabel("Heart Rate")
                if source == .none {
                    NoHRSourceLabel()
                } else if size == .twoByOne {
                    HStack(alignment: .lastTextBaseline, spacing: Spacing.lg) {
                        hero
                        Spacer()
                        stat("Avg", averageBPM)
                        stat("Max", maxBPM)
                    }
                } else {
                    hero
                }
                Spacer()
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cyBgSecondary)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.hrZone(zone))
                .frame(width: Spacing.hrBorderWidth)
        }
        .widgetDetail(label: HeartRateDashboardWidget.title, value: accessibilityValue) {
            HeartRateSheet(metrics: metrics)
        }
    }

    // Over the unit, as Design.sketch draws it: `heroAccessory` would put it before the value.
    private var hero: some View {
        HeroNumber(bpm > 0 ? "\(bpm)" : "—", unit: "bpm")
            .heroNumberSize(.medium)
            .overlay(alignment: .topTrailing) {
                if bpm > 0, trend != .steady {
                    Image(systemName: trend == .up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.system(size: Self.trendSize))
                        .foregroundStyle(trend == .up ? Color.cyRatingGood : Color.cyRatingBad)
                }
            }
    }

    // Stat cells reuse the design-system HeroNumber, matching CadenceWidget.
    private func stat(_ label: String, _ bpm: Int) -> some View {
        HeroNumber(bpm > 0 ? "\(bpm)" : "—", unit: "") { Text(label).font(.caption) }
            .heroNumberSize(.small)
            .layout(.vertical)
    }

    /// What VoiceOver reads after "Heart Rate" (#361): what this size shows, with no "—" read aloud.
    var accessibilityValue: String {
        if source == .none { return "No HR source" }
        guard bpm > 0 else { return "No reading" }
        var parts = ["\(bpm) beats per minute", "zone \(zone)"]
        switch trend {
        case .up: parts.append("rising")
        case .down: parts.append("falling")
        case .steady: break
        }
        if size == .twoByOne {
            if averageBPM > 0 { parts.append("average \(averageBPM)") }
            if maxBPM > 0 { parts.append("maximum \(maxBPM)") }
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - W4 History Watermark

/// `CadenceHistoryChart` for heart rate: the trace as a faint line over the rider's zone bands.
private struct HeartRateHistoryChart: View {
    let history: [Double]   // bpm
    let zoneBounds: [ClosedRange<Int>]

    var body: some View {
        let domain = zoneBounds.chartDomain(including: history)
        Chart {
            HeartRateZoneBands(zoneBounds: zoneBounds, domain: domain, x: 0...Double(max(history.count - 1, 1)))
            ForEach(Array(history.enumerated()), id: \.offset) { index, bpm in
                LineMark(x: .value("t", Double(index)), y: .value("bpm", bpm))
                    .foregroundStyle(Color.cyTextPrimary.opacity(Opacity.lineWatermark))
            }
        }
        .chartYScale(domain: domain)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}

/// The rider's zones as horizontal bands behind a heart-rate trace — W4's watermark and the sheet's
/// chart (UX.md §W4). Each band runs to the next zone's start, so they tile with no seam; the outer
/// two reach the plot's edges.
struct HeartRateZoneBands<X: Plottable & Comparable>: ChartContent {
    let zoneBounds: [ClosedRange<Int>]
    let domain: ClosedRange<Double>
    let x: ClosedRange<X>

    var body: some ChartContent {
        ForEach(Array(zoneBounds.enumerated()), id: \.offset) { index, bounds in
            RectangleMark(
                xStart: .value("t0", x.lowerBound),
                xEnd: .value("t1", x.upperBound),
                yStart: .value("bpm0", index == 0 ? domain.lowerBound : Double(bounds.lowerBound)),
                yEnd: .value("bpm1", index == zoneBounds.count - 1 ? domain.upperBound : Double(bounds.upperBound + 1))
            )
            .foregroundStyle(Color.hrZone(index + 1).opacity(Opacity.zoneBand))
        }
    }
}

extension Array where Element == ClosedRange<Int> {
    /// A heart-rate chart's y-domain over these zone bounds: resting to max, as the zone table
    /// runs, so the bands sit still as the ride goes on, as cadence's do; widened only for a
    /// reading outside it.
    func chartDomain(including readings: [Double]) -> ClosedRange<Double> {
        let low = Swift.min(Double(first?.lowerBound ?? 0), readings.min() ?? .infinity)
        let high = Swift.max(Double(last?.upperBound ?? 0), readings.max() ?? -.infinity)
        return low...Swift.max(high, low + 1)
    }
}

// MARK: - W12 HR Zones

/// W12 — HR Zones, 1×1 and 2×1, from Design.sketch "W12 - Zones" (#145): the ride's time in each
/// zone as a donut beside a row per zone, the current zone bold. 2×1 has no frame of its own; it
/// gives each row its S12 name.
struct HRZonesWidget: View {
    let zone: Int
    let source: HRSource
    /// Recorded seconds per zone, zone 1 first (`State.hrZoneSeconds`).
    var zoneSeconds: [Int] = []
    var size: WidgetSize = .oneByOne
    /// See `HeartRateWidget.metrics`.
    var metrics: () -> HeartRateMetrics = { HeartRateMetrics() }

    /// From Design.sketch "W12 - Zones": the 1×1 donut and each row's colour square.
    private static let donutSize: CGFloat = 54
    private static let swatchSize: CGFloat = 10

    private var hasTime: Bool { zoneSeconds.contains { $0 > 0 } }

    private func seconds(_ zone: HeartRateZone) -> Int {
        zone.rawValue <= zoneSeconds.count ? zoneSeconds[zone.rawValue - 1] : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel("Heart Rate Zones")
            // Time recorded before a dropout is still true, so only a ride with neither a source
            // nor any time reads as empty.
            if source == .none, !hasTime {
                NoHRSourceLabel()
                Spacer()
            } else {
                HStack(alignment: .center, spacing: Spacing.sm) {
                    donut
                        .frame(width: size == .oneByOne ? Self.donutSize : nil)
                        .aspectRatio(1, contentMode: .fit)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(HeartRateZone.allCases, id: \.self) { row($0) }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.cyBgSecondary)
        .widgetDetail(label: HRZonesDashboardWidget.title, value: accessibilityValue) {
            HeartRateSheet(metrics: metrics)
        }
    }

    // Before any time, a neutral ring holds the donut's place.
    private var donut: some View {
        DonutChart(slices: hasTime
            ? HeartRateZone.allCases.map {
                DonutSlice(id: "\($0.rawValue)", value: TimeInterval(seconds($0)), color: .hrZone($0.rawValue))
            }
            : [DonutSlice(id: "none", value: 1, color: .cyBgTertiary)])
    }

    private func row(_ zone: HeartRateZone) -> some View {
        HStack(spacing: Spacing.xs) {
            Rectangle()
                .fill(Color.hrZone(zone.rawValue))
                .frame(width: Self.swatchSize, height: Self.swatchSize)
            if size == .twoByOne {
                Text("Z\(zone.rawValue) \(zone.s12DisplayName)")
                Spacer(minLength: Spacing.xs)
                Text(seconds(zone).formattedElapsed)
            } else {
                Text("Z\(zone.rawValue): \(seconds(zone).formattedElapsed)")
            }
        }
        .font(.caption2.weight(zone.rawValue == self.zone ? .bold : .regular))
        .monospacedDigit()
        .lineLimit(1)
    }

    /// What VoiceOver reads after "HR Zones" (#361): the current zone, then each zone the ride has
    /// spent time in.
    var accessibilityValue: String {
        if source == .none, !hasTime { return "No HR source" }
        let current = zone == 0 ? "No reading" : "Zone \(zone)"
        let times = HeartRateZone.allCases.filter { seconds($0) > 0 }.map {
            "zone \($0.rawValue) \(seconds($0).spokenElapsed)"
        }
        return ([current] + times).joined(separator: "; ")
    }
}

// MARK: - Previews

/// A watermark's worth of points, rolling between Z1 and Z3.
private let previewHistory: [Double] = (0..<60).map { 140 + 14 * sin(Double($0) / 6) }
private let previewZoneSeconds = [312, 846, 702, 318, 42]

#Preview("W4 1×1 — Live") {
    HeartRateWidget(bpm: 156, zone: 3, source: .bleStrap, history: previewHistory, trend: .up,
                    averageBPM: 148, maxBPM: 171, metrics: { .sample })
        .frame(width: 196, height: 96)
}

#Preview("W4 2×1 — Live") {
    HeartRateWidget(bpm: 156, zone: 3, source: .bleStrap, history: previewHistory, trend: .down,
                    averageBPM: 148, maxBPM: 171, size: .twoByOne, metrics: { .sample })
        .frame(width: 393, height: 96)
}

#Preview("W4 — Each zone") {
    VStack(spacing: Spacing.xs) {
        ForEach([118, 145, 156, 170, 182], id: \.self) { bpm in
            HeartRateWidget(bpm: bpm, zone: RiderProfile().zone(forBPM: bpm).rawValue, source: .bleStrap,
                            history: previewHistory)
                .frame(width: 196, height: 96)
        }
    }
}

#Preview("W4 — No reading") {
    HeartRateWidget(bpm: 0, zone: 0, source: .bleStrap, size: .twoByOne)
        .frame(width: 393, height: 96)
}

#Preview("W4 — No HR source") {
    HeartRateWidget(bpm: 0, zone: 0, source: .none)
        .frame(width: 196, height: 96)
}

#Preview("W12 1×1 — Live") {
    HRZonesWidget(zone: 3, source: .bleStrap, zoneSeconds: previewZoneSeconds, metrics: { .sample })
        .frame(width: 196, height: 96)
}

#Preview("W12 2×1 — Live") {
    HRZonesWidget(zone: 3, source: .bleStrap, zoneSeconds: previewZoneSeconds, size: .twoByOne,
                  metrics: { .sample })
        .frame(width: 393, height: 96)
}

#Preview("W12 — No time yet") {
    HRZonesWidget(zone: 2, source: .healthKit)
        .frame(width: 196, height: 96)
}

#Preview("W12 — No HR source") {
    HRZonesWidget(zone: 0, source: .none)
        .frame(width: 196, height: 96)
}

#Preview("W4 + W12 — Dark") {
    HStack(spacing: 0) {
        HeartRateWidget(bpm: 170, zone: 4, source: .bleStrap, history: previewHistory, trend: .up,
                        metrics: { .sample })
        HRZonesWidget(zone: 4, source: .bleStrap, zoneSeconds: previewZoneSeconds, metrics: { .sample })
    }
    .frame(width: 393, height: 96)
    .preferredColorScheme(.dark)
}
