import Charts
import SwiftUI

// MARK: - W1 Speed Widget

struct SpeedWidget: View {
    let speed: Double?          // m/s; nil → "—"
    let speedHistory: [Double]  // m/s samples for watermark chart
    let activeSpeedSource: SensorSource
    let distance: Double        // meters
    let elapsed: Int            // seconds
    let averageSpeed: Double    // m/s
    let maxSpeed: Double        // m/s
    var unit: UnitSystem = .metric
    var size: WidgetSize = .twoByTwo
    /// The Ride Metrics sheet's data. A closure so the card never reads it; only the open sheet does,
    /// in its own body (#144).
    var metrics: () -> RideMetrics = { RideMetrics() }

    // Hero number scales proportionally to slot height: the large-hero spec is
    // `heroNominalFont`pt in a `heroNominalHeight`pt 2×2 slot, floored at
    // `heroMinFont`pt for the compact slots.
    private static let heroNominalFont: CGFloat = 136
    private static let heroNominalHeight: CGFloat = 200
    private static let heroMinFont: CGFloat = 34

    var body: some View {
        ZStack {
            if size != .oneByOne, !speedHistory.isEmpty {
                SpeedHistoryChart(history: speedHistory, unit: unit)
                    .opacity(Opacity.watermark)
            }
            GeometryReader { geo in
                switch size {
                case .twoByTwo: twoByTwoContent(geo)
                case .twoByOne: twoByOneContent(geo)
                case .oneByOne: oneByOneContent(geo)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cyBgSecondary)
        .widgetDetail(label: SpeedDashboardWidget.title, value: accessibilityValue) {
            RideMetricsSheet(metrics: metrics)
        }
    }

    // MARK: - Layout Variants

    @ViewBuilder
    private func twoByTwoContent(_ geo: GeometryProxy) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                speedHero(fontSize: heroFontSize(for: geo.size.height))
                Spacer()
                // Distance must never truncate — it takes the width it needs and
                // pushes Time to the right (Time yields space first).
                HStack(alignment: .firstTextBaseline, spacing: Spacing.lg) {
                    distanceStat
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                    timeStat
                }
            }
            .padding(Spacing.sm)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                sourceBadge
                    .padding(.top, Spacing.sm)
                    .padding(.leading, Spacing.sm)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Spacing.lg) {
                avgStat
                maxStat
            }
            .padding(Spacing.sm)
        }
    }

    @ViewBuilder
    private func twoByOneContent(_ geo: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.xs) {
                speedTitle
                sourceBadge
            }
            HStack(alignment: .lastTextBaseline, spacing: Spacing.lg) {
                speedHero(fontSize: heroFontSize(for: geo.size.height))
                Spacer()
                avgStat
                maxStat
            }
            Spacer()
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func oneByOneContent(_ geo: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            speedTitle
            speedHero(fontSize: heroFontSize(for: geo.size.height))
            Spacer()
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: - Sub-Views

    private func speedHero(fontSize: CGFloat) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: Spacing.xs) {
            Text(displaySpeed)
                .dDINCondensed(size: fontSize, relativeTo: .largeTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                // Measured from the rendered baseline, so it holds when the text scales down.
                .alignmentGuide(.heroCapTop) { $0[.firstTextBaseline] * (1 - Self.capHeightToAscent) }
                // Right of the value, level with the tops of its digits. An overlay, so the unit
                // keeps its place (#81).
                .overlay(alignment: Alignment(horizontal: .trailing, vertical: .heroCapTop)) {
                    trendIndicator
                        .font(.title3)
                        .alignmentGuide(.trailing) { $0[.leading] - Spacing.xs }
                        // The glyph's top, not its frame's: a symbol's frame has room above it.
                        .alignmentGuide(.heroCapTop) { $0[.firstTextBaseline] - Self.trendCapHeight }
                }
            if speed != nil {
                Text(unit.speedLabel)
                    .font(.footnote)
                    .textCase(.lowercase)
            }
        }
    }

    // Stat cells reuse the design-system HeroNumber. Labels are authored in
    // Title case; HeroNumber renders them ALL-CAPS via `.textCase`.
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

    private var distanceStat: some View {
        HeroNumber(displayDistance, unit: unit.distanceLabel) { Text("Distance").font(.caption) }
            .heroNumberSize(.small)
    }

    private var timeStat: some View {
        HeroNumber(elapsed.formattedElapsed, unit: "") { Text("Time").font(.caption) }
            .heroNumberSize(.small)
    }

    private var speedTitle: some View {
        WidgetLabel("Speed")
    }

    private var sourceBadge: some View {
        let (label, fg, bg): (String, Color, Color) = switch activeSpeedSource {
        case .gps:      ("GPS", .cyTextOnPrimary, .cyPrimary)
        case .bleWheel: ("BLE", .cyTextOnPrimary, .cyPrimary)
        case .bleHR, .bleCadence, .blePower, .appleWatch, .none:
                        ("--",  .cyTextTertiary,  .cyBgTertiary)
        }
        return Text(label)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 2)
            .foregroundStyle(fg)
            .background(bg, in: Capsule())
    }

    // MARK: - Computed Display Values

    /// One-decimal number format shared by every value in the widget.
    private func oneDecimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    private var displaySpeed: String {
        guard let s = speed else { return "—" }
        return oneDecimal(unit.speed(fromMPS: s))
    }

    private var displayAvg: String { oneDecimal(unit.speed(fromMPS: averageSpeed)) }
    private var displayMax: String { oneDecimal(unit.speed(fromMPS: maxSpeed)) }
    private var displayDistance: String { oneDecimal(unit.distance(fromMeters: distance)) }

    /// What VoiceOver reads after "Speed" (#361): what this size shows, with no "—" read aloud. Units
    /// and time are spelled out: VoiceOver reads "1:02:33" digit by digit, and a symbol is a guess.
    var accessibilityValue: String {
        var parts = [speed.map(unit.spokenSpeed(fromMPS:)) ?? "No reading"]
        if size != .oneByOne {
            parts += ["average \(displayAvg)", "maximum \(displayMax)"]
        }
        if size == .twoByTwo {
            parts += ["distance \(unit.spokenDistance(fromMeters: distance))", "time \(elapsed.spokenElapsed)"]
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Trend Indicator

    private enum Trend: Equatable { case up, even, down }

    /// Minimum delta from the ride average before the trend indicator shows
    /// ▲/▼. Compared in canonical m/s (≈0.5 km/h) so sensitivity is
    /// identical regardless of the display unit.
    private static let trendThresholdMPS = 0.14

    private var trend: Trend {
        guard let s = speed, averageSpeed > 0 else { return .even }
        let diff = s - averageSpeed
        if diff > Self.trendThresholdMPS { return .up }
        if diff < -Self.trendThresholdMPS { return .down }
        return .even
    }

    /// Current speed against the ride average, as W4's ▲/▼; hidden when even or with no reading.
    @ViewBuilder
    private var trendIndicator: some View {
        switch trend {
        case .up:   Image(systemName: "arrowtriangle.up.fill").foregroundStyle(Color.cyRatingGood)
        case .down: Image(systemName: "arrowtriangle.down.fill").foregroundStyle(Color.cyRatingBad)
        case .even: EmptyView()
        }
    }

    /// Cap height of the indicator's `.title3`, which its ▲/▼ is drawn to.
    private static var trendCapHeight: CGFloat { UIFont.preferredFont(forTextStyle: .title3).capHeight }

    /// D-DIN's cap height as a share of its ascent: where the digits' tops sit between the hero's
    /// top and its baseline, at any size.
    private static let capHeightToAscent: CGFloat = {
        guard let font = UIFont(name: AppFonts.dDINCondensedPostScriptName, size: 100) else { return 0 }
        return font.capHeight / font.ascender
    }()

    // Scale the large-hero font proportionally to the available slot height.
    private func heroFontSize(for height: CGFloat) -> CGFloat {
        max(Self.heroMinFont, Self.heroNominalFont * (height / Self.heroNominalHeight))
    }
}

private extension VerticalAlignment {
    /// The top of the speed hero's digits.
    enum HeroCapTop: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[.top] }
    }
    static let heroCapTop = VerticalAlignment(HeroCapTop.self)
}

// MARK: - Speed History Watermark Chart

private struct SpeedHistoryChart: View {
    let history: [Double]   // m/s
    let unit: UnitSystem

    var body: some View {
        Chart(Array(history.enumerated()), id: \.offset) { index, mps in
            let displaySpeed = unit.speed(fromMPS: mps)
            AreaMark(
                x: .value("t", index),
                y: .value("speed", displaySpeed)
            )
            .foregroundStyle(Color.cyPrimary)
            LineMark(
                x: .value("t", index),
                y: .value("speed", displaySpeed)
            )
            .foregroundStyle(Color.cyPrimary)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}

// MARK: - Helpers

extension Int {
    /// Seconds in words, "1 hour, 2 minutes, 33 seconds": VoiceOver reads "1:02:33" digit by
    /// digit (#361).
    var spokenElapsed: String {
        Duration.seconds(self).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }

    var formattedElapsed: String {
        let d = Duration.seconds(self)
        if self >= 3600 {
            return d.formatted(.time(pattern: .hourMinuteSecond(padHourToLength: 1, fractionalSecondsLength: 0)))
        } else {
            return d.formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2, fractionalSecondsLength: 0)))
        }
    }
}

// MARK: - Previews

#Preview("2×2 — Active") {
    SpeedWidget(
        speed: 7.89,
        speedHistory: stride(from: 4.0, to: 9.5, by: 0.15).map { $0 },
        activeSpeedSource: .gps,
        distance: 12_300,
        elapsed: 2340,
        averageSpeed: 7.89,
        maxSpeed: 9.47,
        unit: .metric,
        size: .twoByTwo
    )
    .frame(width: 393, height: 200)
}

#Preview("2×2 — No Signal") {
    SpeedWidget(
        speed: nil,
        speedHistory: [],
        activeSpeedSource: .none,
        distance: 0,
        elapsed: 0,
        averageSpeed: 0,
        maxSpeed: 0,
        unit: .metric,
        size: .twoByTwo
    )
    .frame(width: 393, height: 200)
}

#Preview("2×1") {
    SpeedWidget(
        speed: 7.89,
        speedHistory: stride(from: 4.0, to: 9.5, by: 0.3).map { $0 },
        activeSpeedSource: .gps,
        distance: 12_300,
        elapsed: 2340,
        averageSpeed: 7.89,
        maxSpeed: 9.47,
        unit: .metric,
        size: .twoByOne
    )
    .frame(width: 393, height: 96)
}

#Preview("1×1") {
    SpeedWidget(
        speed: 7.89,
        speedHistory: [],
        activeSpeedSource: .gps,
        distance: 12_300,
        elapsed: 2340,
        averageSpeed: 7.89,
        maxSpeed: 9.47,
        unit: .metric,
        size: .oneByOne
    )
    .frame(width: 196, height: 96)
}

#Preview("Imperial") {
    SpeedWidget(
        speed: 7.89,
        speedHistory: stride(from: 4.0, to: 9.5, by: 0.15).map { $0 },
        activeSpeedSource: .gps,
        distance: 12_300,
        elapsed: 2340,
        averageSpeed: 7.89,
        maxSpeed: 9.47,
        unit: .imperial,
        size: .twoByTwo
    )
    .frame(width: 393, height: 200)
}
