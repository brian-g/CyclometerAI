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
    let cadenceHistory: [Double] // rpm samples for watermark chart
    let averageCadence: Int      // rpm; 0 → no pedalling recorded yet
    let maxCadence: Int          // rpm
    /// Everything only the detail sheet needs. A closure so the dashboard never reads these
    /// (large, fast-changing) arrays itself — only the presented sheet does.
    var detail: () -> CadenceDetail = { CadenceDetail() }
    var size: WidgetSize = .twoByOne   // only .oneByOne / .twoByOne used by W5

    @State private var showDetail = false

    var body: some View {
        ZStack {
            if !cadenceHistory.isEmpty {
                CadenceHistoryChart(history: cadenceHistory)
            }
            switch size {
            case .oneByOne, .twoByTwo: oneByOneContent
            case .twoByOne:            twoByOneContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cyBgSecondary)
        .contentShape(Rectangle())
        .onTapGesture { showDetail = true }
        .sheet(isPresented: $showDetail) {
            CadenceDetailSheet(
                averageCadence: averageCadence,
                maxCadence: maxCadence,
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
}

// MARK: - Cadence History Watermark Chart

private struct CadenceHistoryChart: View {
    let history: [Double]   // rpm

    /// Fixed y-domain so the zone bands always map to the same screen positions
    /// regardless of the ride's actual cadence range. 150 covers sprint/over-spin
    /// cadences so the line and red over-spin band aren't clipped above 130.
    private static let yMax: Double = 150

    var body: some View {
        Chart {
            // Coloured zone bands behind the cadence line (issue #38).
            ForEach(Array(CadenceZone.allCases.enumerated()), id: \.offset) { _, zone in
                let range = zone.rpmRange(ceiling: Self.yMax)
                RectangleMark(
                    xStart: .value("t0", 0),
                    xEnd: .value("t1", max(history.count - 1, 1)),
                    yStart: .value("rpm0", range.lowerBound),
                    yEnd: .value("rpm1", range.upperBound)
                )
                .foregroundStyle(zone.color.opacity(Opacity.zoneBand))
            }

            // Cadence trace as a line over the bands. No area fill — it would tint
            // the lower (grinding/optimal) bands and defeat the at-a-glance read.
            ForEach(Array(history.enumerated()), id: \.offset) { index, rpm in
                LineMark(x: .value("t", index), y: .value("rpm", rpm))
                    .foregroundStyle(Color.cyTextPrimary.opacity(Opacity.lineWatermark))
            }
        }
        .chartYScale(domain: 0...Self.yMax)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}

// MARK: - Donut Chart

private struct DonutSlice: Identifiable {
    let id: String
    let value: TimeInterval
    let color: Color
}

/// Share of time per slice. Purely decorative: the rows beside it carry the values.
private struct DonutChart: View {
    let slices: [DonutSlice]

    private static let innerRadiusRatio = 0.6

    var body: some View {
        Chart(slices.filter { $0.value > 0 }) { slice in
            SectorMark(
                angle: .value("Time", slice.value),
                innerRadius: .ratio(Self.innerRadiusRatio),
                angularInset: 1
            )
            .foregroundStyle(slice.color)
        }
        .chartLegend(.hidden)
        .accessibilityHidden(true)
    }
}

// MARK: - Cadence Detail Chart

/// Cadence over time on zone bands, with the ride's elevation as a faint watermark behind.
private struct CadenceDetailChart: View {
    let cadenceSamples: [CadenceSample]
    let altitudeSamples: [AltitudeSample]

    private static let yMax: Double = 150
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
    /// same strategy as `CadenceFeature.watermarkSamples`, keeping a full hour of 1 Hz
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
                ForEach(Array(CadenceZone.allCases.enumerated()), id: \.offset) { _, zone in
                    let bounds = zone.rpmRange(ceiling: Self.yMax)
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
                            altitudeSamples: detail.altitudeSamples
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
                            DonutSlice(id: $0.label, value: zoneSeconds[$0] ?? 0, color: $0.color)
                        })
                        .frame(height: Self.donutHeight)
                        .frame(maxWidth: .infinity)
                    }
                    ForEach(CadenceZone.allCases, id: \.self) { zone in
                        metricRow("\(zone.label) rpm", Self.duration(zoneSeconds[zone] ?? 0))
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

private let demoHistory: [Double] = stride(from: 60.0, to: 105.0, by: 1.2).map { $0 }

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
        detail: CadenceDetail(
            cadenceSamples: demoCadenceSamples,
            altitudeSamples: demoAltitudeSamples,
            zoneSeconds: [.grinding: 95, .transition: 210, .optimal: 1_260, .overspin: 42],
            coastingSeconds: 380
        )
    )
}

#Preview("Detail Sheet — No Data") {
    CadenceDetailSheet(averageCadence: 0, maxCadence: 0, detail: CadenceDetail())
}
