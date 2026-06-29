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

    @State private var showDetail = false

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
        .onTapGesture { showDetail = true }
        .sheet(isPresented: $showDetail) {
            Text("Ride Metrics")
                .font(.headline)
                .presentationDetents([.medium])
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
            .heroAccessory { trendChevron }
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
        case .none:     ("--",  .cyTextTertiary,  .cyBgTertiary)
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

    // MARK: - Trend Chevron

    private enum Trend: Equatable { case up, even, down }

    /// Minimum delta from the ride average before the trend chevron points
    /// up/down. Compared in canonical m/s (≈0.5 km/h) so sensitivity is
    /// identical regardless of the display unit.
    private static let trendThresholdMPS = 0.14
    /// Chevron tilt (degrees) for up (negative) / down (positive) trend.
    private static let chevronTiltDegrees: Double = 45

    private var trend: Trend {
        guard let s = speed, averageSpeed > 0 else { return .even }
        let diff = s - averageSpeed
        if diff > Self.trendThresholdMPS { return .up }
        if diff < -Self.trendThresholdMPS { return .down }
        return .even
    }

    private var trendChevron: some View {
        let tilt = trend == .up ? -Self.chevronTiltDegrees
                 : trend == .down ? Self.chevronTiltDegrees : 0
        return Image(systemName: "chevron.forward.circle.fill")
            .foregroundStyle(
                trend == .up   ? Color.cyRatingGood :
                trend == .down ? Color.cyRatingBad  : Color.secondary
            )
            .rotationEffect(.degrees(tilt))
            .animation(.easeInOut(duration: 0.3), value: trend)
    }

    // Scale the large-hero font proportionally to the available slot height.
    private func heroFontSize(for height: CGFloat) -> CGFloat {
        max(Self.heroMinFont, Self.heroNominalFont * (height / Self.heroNominalHeight))
    }
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
