import Charts
import SwiftUI

// MARK: - Cadence Detail Data

/// What the W5 detail sheet shows beyond the widget face.
struct CadenceDetail: Equatable {
    var cadenceSamples: [CadenceSample] = []
    var altitudeSamples: [AltitudeSample] = []
    /// Pedalling time per zone.
    var zoneSeconds: [CadenceZone: TimeInterval] = [:]
    var coastingSeconds: TimeInterval = 0

    init(cadenceSamples: [CadenceSample] = [], altitudeSamples: [AltitudeSample] = [],
         zoneSeconds: [CadenceZone: TimeInterval] = [:], coastingSeconds: TimeInterval = 0) {
        self.cadenceSamples = cadenceSamples
        self.altitudeSamples = altitudeSamples
        self.zoneSeconds = zoneSeconds
        self.coastingSeconds = coastingSeconds
    }

    init(cadence: CadenceFeature.State, altitudeSamples: [AltitudeSample]) {
        self.init(
            cadenceSamples: cadence.cadenceSamples,
            altitudeSamples: altitudeSamples,
            zoneSeconds: cadence.zoneSeconds,
            coastingSeconds: cadence.coastingSeconds
        )
    }
}

// MARK: - W5 Cadence Widget

struct CadenceWidget: View {
    let cadence: Int?            // rpm; nil → "—"
    let cadenceHistory: [WatermarkPoint] // rpm, for the watermark chart
    /// The time span the watermark plots over, shared with the other widgets' watermarks
    /// (`ActiveRideFeature.State.watermarkWindow`). Nil plots the history's own span.
    var watermarkWindow: ClosedRange<Date>? = nil
    let averageCadence: Int      // rpm; 0 → no pedalling recorded yet
    let maxCadence: Int          // rpm
    /// The rider's S12 cadence zones (#79), drawn as the watermark's bands.
    var zones: CadenceZoneBoundaries = .default
    /// Everything only the detail sheet needs. A closure so the dashboard never reads these
    /// (large, fast-changing) arrays itself — only the presented sheet does.
    var detail: () -> CadenceDetail = { CadenceDetail() }
    var size: WidgetSize = .twoByOne   // only .oneByOne / .twoByOne used by W5

    var body: some View {
        ZStack {
            // Drawn with or without readings (#79): the bands are the rider's zones, not data.
            CadenceHistoryChart(history: cadenceHistory, window: watermarkWindow, zones: zones)
            switch size {
            case .oneByOne, .twoByTwo: oneByOneContent
            case .twoByOne:            twoByOneContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cyBgSecondary)
        .widgetDetail(label: CadenceDashboardWidget.title, value: accessibilityValue) {
            CadenceDetailSheet(
                averageCadence: averageCadence,
                maxCadence: maxCadence,
                zones: zones,
                detail: detail()
            )
        }
    }

    // MARK: - Layout Variants

    private var oneByOneContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel("Cadence")
            cadenceHero
            Spacer()
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var twoByOneContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel("Cadence")
            HStack(alignment: .lastTextBaseline, spacing: Spacing.lg) {
                cadenceHero
                Spacer()
                avgStat
                maxStat
            }
            Spacer()
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sub-Views

    // Current value reuses the design-system HeroNumber at medium-hero (68pt),
    // matching the sibling 1×1 widgets (HR, Pace). Unit shown only when paired.
    private var cadenceHero: some View {
        HeroNumber(displayCadence, unit: cadence != nil ? "rpm" : "")
            .heroNumberSize(.medium)
            .heroTrend(Self.trend(cadence: cadence, average: averageCadence))
    }

    // MARK: - Trend

    /// Minimum difference from the ride average before the trend indicator shows ▲/▼ (#402).
    static let trendThresholdRPM = 5

    /// Current cadence against the ride average, as W1's speed is (#402). Steady when coasting,
    /// with no reading, or before any pedalling has been recorded.
    static func trend(cadence: Int?, average: Int) -> Trend {
        guard let cadence, cadence > 0, average > 0 else { return .steady }
        let diff = cadence - average
        if diff > trendThresholdRPM { return .up }
        if diff < -trendThresholdRPM { return .down }
        return .steady
    }

    // Stat cells reuse the design-system HeroNumber, matching SpeedWidget.
    private var avgStat: some View {
        HeroNumber(displayAvg, unit: "") { Text("Avg").font(.caption) }
            .heroNumberSize(.small)
            .layout(.vertical)
    }

    private var maxStat: some View {
        HeroNumber(displayMax, unit: "") { Text("Max").font(.caption) }
            .heroNumberSize(.small)
            .layout(.vertical)
    }

    // MARK: - Computed Display Values

    private var displayCadence: String { cadence.map(String.init) ?? "—" }
    /// Avg/Max read "—" until at least one pedalling reading exists (0 rpm average
    /// is meaningless — it would mean the rider never pedalled).
    private var displayAvg: String { averageCadence > 0 ? "\(averageCadence)" : "—" }
    private var displayMax: String { maxCadence > 0 ? "\(maxCadence)" : "—" }

    /// What VoiceOver reads after "Cadence" (#361): what this size shows, with no "—" read aloud.
    var accessibilityValue: String {
        var parts = [cadence.map { "\($0) rpm" } ?? "No reading"]
        // The ▲/▼ on the cadence, read as W1's (#401).
        switch Self.trend(cadence: cadence, average: averageCadence) {
        case .up: parts.append("above average")
        case .down: parts.append("below average")
        case .steady: break
        }
        if size == .twoByOne {
            if averageCadence > 0 { parts.append("average \(averageCadence)") }
            if maxCadence > 0 { parts.append("maximum \(maxCadence)") }
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Cadence History Watermark Chart

private struct CadenceHistoryChart: View {
    let history: [WatermarkPoint]   // rpm
    let window: ClosedRange<Date>?
    let zones: CadenceZoneBoundaries

    /// Fixed y-domain so the zone bands always map to the same screen positions
    /// regardless of the ride's actual cadence range. 150 covers sprint cadences, and
    /// S12 keeps every zone boundary below it so the Z5 band always shows.
    private static let yMax = Double(CadenceZoneBoundaries.ceilingRPM)

    var body: some View {
        let domain = history.plotDomain(window)
        Chart {
            // Coloured zone bands behind the cadence line (#38, #79).
            ForEach(CadenceZone.allCases, id: \.self) { zone in
                let range = zones.bandRange(for: zone, ceiling: Self.yMax)
                RectangleMark(
                    xStart: .value("t0", domain.lowerBound),
                    xEnd: .value("t1", domain.upperBound),
                    yStart: .value("rpm0", range.lowerBound),
                    yEnd: .value("rpm1", range.upperBound)
                )
                .foregroundStyle(zone.color.opacity(Opacity.zoneBand))
            }

            // Cadence trace as a line over the bands. No area fill — it would tint
            // the lower bands and defeat the at-a-glance read. One series per run, so a silence
            // breaks the line rather than being drawn across.
            ForEach(Array(history.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("t", point.time), y: .value("rpm", point.value), series: .value("run", point.run))
                    .foregroundStyle(Color.cyTextPrimary.opacity(Opacity.lineWatermark))
            }
            ForEach(Array(history.lonePoints.enumerated()), id: \.offset) { _, point in
                PointMark(x: .value("t", point.time), y: .value("rpm", point.value))
                    .symbolSize(CGSize(width: Spacing.watermarkDot, height: Spacing.watermarkDot))
                    .foregroundStyle(Color.cyTextPrimary.opacity(Opacity.lineWatermark))
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...Self.yMax)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        // A lone reading's dot at the domain's edge would otherwise draw into the next cell.
        .clipped()
    }
}

// MARK: - Cadence Detail Chart

/// Cadence over time on zone bands, with the ride's elevation as a faint watermark behind.
private struct CadenceDetailChart: View {
    let cadenceSamples: [CadenceSample]
    let altitudeSamples: [AltitudeSample]
    let zones: CadenceZoneBoundaries

    private static let yMax = Double(CadenceZoneBoundaries.ceilingRPM)
    /// Elevation is normalised into the cadence y-domain (a chart has one y-scale), so it
    /// only fills the lower part of it and never competes with the cadence trace.
    private static let elevationHeightFraction = 0.6
    /// Smallest elevation span that is stretched to full watermark height. Below it (GPS
    /// noise on a flat ride) the profile stays flat rather than amplifying jitter.
    private static let minElevationSpanMeters = RouteGeometry.elevationNoiseThresholdMeters
    private static let yAxisValues: [Double] = [0, 50, 100, 150]
    /// Marks plotted per series. A cap, not a target: a short ride has fewer.
    private static let maxPlottedPoints = 120

    private var timeRange: ClosedRange<Date>? {
        guard let first = cadenceSamples.first?.time, let last = cadenceSamples.last?.time,
              first < last else { return nil }
        return first...last
    }

    /// A time-stamped value with the time as its identity, so marks keep their identity as
    /// the series grows instead of being re-diffed by array offset.
    private struct Point: Identifiable {
        let time: Date
        let value: Double
        var id: Date { time }
    }

    /// At most `maxPlottedPoints`, by averaging contiguous buckets (time and value) — the
    /// same strategy as `SpeedSample.bucketAveraged`, keeping a full hour of 1 Hz
    /// readings from becoming thousands of marks.
    private static func downsampled(_ points: [Point]) -> [Point] {
        guard points.count > maxPlottedPoints else { return points }
        let bucket = Double(points.count) / Double(maxPlottedPoints)
        return (0..<maxPlottedPoints).map { i in
            let start = Int(Double(i) * bucket)
            let end = min(max(start + 1, Int(Double(i + 1) * bucket)), points.count)
            let slice = points[start..<end]
            let meanTime = slice.map(\.time.timeIntervalSinceReferenceDate).reduce(0, +) / Double(slice.count)
            return Point(
                time: Date(timeIntervalSinceReferenceDate: meanTime),
                value: slice.map(\.value).reduce(0, +) / Double(slice.count)
            )
        }
    }

    private var cadencePoints: [Point] {
        Self.downsampled(cadenceSamples.map { Point(time: $0.time, value: $0.rpm) })
    }

    /// Elevation as heights within the cadence y-domain, over the cadence time span.
    private var elevationPoints: [Point] {
        guard let range = timeRange else { return [] }
        let visible = altitudeSamples.filter { range.contains($0.time) }
        guard let low = visible.map(\.meters).min(), let high = visible.map(\.meters).max() else { return [] }
        let span = max(high - low, Self.minElevationSpanMeters)
        return Self.downsampled(visible.map {
            Point(time: $0.time, value: ($0.meters - low) / span * Self.yMax * Self.elevationHeightFraction)
        })
    }

    var body: some View {
        let cadence = cadencePoints
        let elevation = elevationPoints
        Chart {
            if let range = timeRange {
                ForEach(CadenceZone.allCases, id: \.self) { zone in
                    let bounds = zones.bandRange(for: zone, ceiling: Self.yMax)
                    RectangleMark(
                        xStart: .value("t0", range.lowerBound),
                        xEnd: .value("t1", range.upperBound),
                        yStart: .value("rpm0", bounds.lowerBound),
                        yEnd: .value("rpm1", bounds.upperBound)
                    )
                    .foregroundStyle(zone.color.opacity(Opacity.zoneBand))
                }
            }

            ForEach(elevation) { point in
                AreaMark(
                    x: .value("t", point.time),
                    yStart: .value("base", 0),
                    yEnd: .value("elevation", point.value),
                    series: .value("Series", "elevation")
                )
                .foregroundStyle(Color.cyTextPrimary.opacity(Opacity.watermark))
            }

            ForEach(cadence) { point in
                LineMark(
                    x: .value("t", point.time),
                    y: .value("rpm", point.value),
                    series: .value("Series", "cadence")
                )
                .foregroundStyle(Color.cyTextPrimary)
            }
        }
        .chartYScale(domain: 0...Self.yMax)
        .chartYAxis {
            AxisMarks(values: Self.yAxisValues)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) {
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .chartLegend(.hidden)
    }
}

// MARK: - Cadence Detail Sheet

/// W5 "Ride metrics" sheet (UX.md §W5): cadence chart over elevation, average and max
/// cadence, pedalling vs coasting, and time in each cadence zone, all from ride state.
/// Cadence smoothness is not shown — no spec defines it.
private struct CadenceDetailSheet: View {
    let averageCadence: Int
    let maxCadence: Int
    let zones: CadenceZoneBoundaries
    let detail: CadenceDetail

    @Environment(\.dismiss) private var dismiss

    private static let chartHeight: CGFloat = 140
    private static let donutHeight: CGFloat = 120
    private static let smallDonutSize: CGFloat = 28

    private var zoneSeconds: [CadenceZone: TimeInterval] { detail.zoneSeconds }
    private var coastingSeconds: TimeInterval { detail.coastingSeconds }
    private var pedalingSeconds: TimeInterval { zoneSeconds.values.reduce(0, +) }

    var body: some View {
        NavigationStack {
            List {
                if detail.cadenceSamples.count > 1 {
                    Section {
                        CadenceDetailChart(
                            cadenceSamples: detail.cadenceSamples,
                            altitudeSamples: detail.altitudeSamples,
                            zones: zones
                        )
                            .frame(height: Self.chartHeight)
                    }
                }
                metricRow("Avg Cadence", averageCadence > 0 ? "\(averageCadence) rpm" : "—")
                metricRow("Max Cadence", maxCadence > 0 ? "\(maxCadence) rpm" : "—")
                pedalingVsCoastingRow
                Section("Time in Cadence Zones") {
                    if pedalingSeconds > 0 {
                        DonutChart(slices: CadenceZone.allCases.map {
                            DonutSlice(id: $0.displayName, value: zoneSeconds[$0] ?? 0, color: $0.color)
                        })
                        .frame(height: Self.donutHeight)
                        .frame(maxWidth: .infinity)
                    }
                    ForEach(CadenceZone.allCases, id: \.self) { zone in
                        metricRow("Z\(zone.rawValue) \(zone.displayName) · \(zones.rangeText(for: zone)) rpm",
                                  Self.duration(zoneSeconds[zone] ?? 0))
                    }
                }
            }
            .navigationTitle("Cadence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var pedalingVsCoastingRow: some View {
        LabeledContent("Pedaling vs Coasting") {
            HStack(spacing: Spacing.sm) {
                Text(pedalingVsCoasting)
                if pedalingSeconds + coastingSeconds > 0 {
                    DonutChart(slices: [
                        DonutSlice(id: "pedaling", value: pedalingSeconds, color: .cyPrimary),
                        DonutSlice(id: "coasting", value: coastingSeconds, color: .cyTextTertiary)
                    ])
                    .frame(width: Self.smallDonutSize, height: Self.smallDonutSize)
                }
            }
        }
    }

    private var pedalingVsCoasting: String {
        let total = pedalingSeconds + coastingSeconds
        guard total > 0 else { return "—" }
        let pedalingPercent = Int((pedalingSeconds / total * 100).rounded())
        return "\(pedalingPercent)% / \(100 - pedalingPercent)%"
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .hourMinuteSecond(padHourToLength: 1)))
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        LabeledContent(label, value: value)
    }
}

// MARK: - Previews

private let demoWindow = demoCadenceSamples.first!.time...demoCadenceSamples.last!.time
private let demoHistory = Watermark.points(demoCadenceSamples, over: demoWindow, time: \.time, value: \.rpm)
/// The sensor asleep through a 10-minute stop: no readings at all, not zeros.
private let demoGapHistory = Watermark.points(
    demoCadenceSamples.enumerated().filter { !(60..<120).contains($0.offset) }.map(\.element),
    over: demoWindow, time: \.time, value: \.rpm
)

#Preview("2×1 — Active") {
    CadenceWidget(
        cadence: 92,
        cadenceHistory: demoHistory,
        averageCadence: 88,
        maxCadence: 104,
        size: .twoByOne
    )
    .frame(width: 393, height: 96)
}

#Preview("2×1 — No Signal") {
    CadenceWidget(
        cadence: nil,
        cadenceHistory: [],
        averageCadence: 0,
        maxCadence: 0,
        size: .twoByOne
    )
    .frame(width: 393, height: 96)
}

#Preview("1×1 — Active") {
    CadenceWidget(
        cadence: 92,
        cadenceHistory: demoHistory,
        averageCadence: 88,
        maxCadence: 104,
        size: .oneByOne
    )
    .frame(width: 196, height: 96)
}

#Preview("2×1 — Sensor gap") {
    CadenceWidget(
        cadence: 92,
        cadenceHistory: demoGapHistory,
        watermarkWindow: demoWindow,
        averageCadence: 88,
        maxCadence: 104,
        size: .twoByOne
    )
    .frame(width: 393, height: 96)
}

#Preview("1×1 — No Signal") {
    CadenceWidget(
        cadence: nil,
        cadenceHistory: [],
        averageCadence: 0,
        maxCadence: 0,
        size: .oneByOne
    )
    .frame(width: 196, height: 96)
}

private let demoStart = Date(timeIntervalSince1970: 1_000_000)

/// One reading every 10 s for 30 min: rpm climbs through the zones with a coasting gap.
private let demoCadenceSamples: [CadenceSample] = (0..<180).map { i in
    let rpm = (70...74).contains(i / 6 % 30) ? 0 : 60 + 45 * abs(sin(Double(i) / 25))
    return CadenceSample(time: demoStart.addingTimeInterval(Double(i) * 10), rpm: rpm)
}

/// A climb then a descent over the same 30 min.
private let demoAltitudeSamples: [AltitudeSample] = (0..<180).map { i in
    AltitudeSample(time: demoStart.addingTimeInterval(Double(i) * 10), meters: 120 + 80 * sin(Double(i) / 57))
}

#Preview("Detail Sheet — Active") {
    CadenceDetailSheet(
        averageCadence: 88,
        maxCadence: 104,
        zones: .default,
        detail: CadenceDetail(
            cadenceSamples: demoCadenceSamples,
            altitudeSamples: demoAltitudeSamples,
            zoneSeconds: [.zone1: 95, .zone2: 210, .zone3: 1_260, .zone4: 300, .zone5: 42],
            coastingSeconds: 380
        )
    )
}

#Preview("Detail Sheet — No Data") {
    CadenceDetailSheet(averageCadence: 0, maxCadence: 0, zones: .default, detail: CadenceDetail())
}
