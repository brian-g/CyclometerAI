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

    var body: some View {
        ZStack {
            if size != .oneByOne, !speedHistory.isEmpty {
                SpeedHistoryChart(history: speedHistory, unit: unit)
                    .opacity(0.2)
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
        let heroSize = heroFontSize(for: geo.size.height)
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                speedHero(fontSize: heroSize)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: Spacing.lg) {
                    HeroNumber(displayDistance, unit: unit.distanceLabel) {
                        Text("Distance").font(.caption)
                    }
                    .heroNumberSize(.small)
                    HeroNumber(elapsed.formattedElapsed, unit: "") {
                        Text("Time").font(.caption)
                    }
                    .heroNumberSize(.small)
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
                statCell(label: "Avg", value: displayAvg, showChevron: true)
                statCell(label: "Max", value: displayMax)
            }
            .padding(Spacing.sm)
        }
    }

    @ViewBuilder
    private func twoByOneContent(_ geo: GeometryProxy) -> some View {
        let heroSize = heroFontSize(for: geo.size.height)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.xs) {
                speedTitle
                sourceBadge
            }
            HStack(alignment: .lastTextBaseline, spacing: Spacing.lg) {
                speedHero(fontSize: heroSize)
                Spacer()
                statCell(label: "AVG", value: displayAvg, labelFont: .caption2, showChevron: true)
                statCell(label: "MAX", value: displayMax, labelFont: .caption2)
            }
            Spacer()
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func oneByOneContent(_ geo: GeometryProxy) -> some View {
        let heroSize = heroFontSize(for: geo.size.height)
        VStack(alignment: .leading, spacing: 0) {
            speedTitle
            speedHero(fontSize: heroSize)
            Spacer()
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: - Sub-Views

    @ViewBuilder
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

    private var speedTitle: some View {
        Text("SPEED")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
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

    private var displaySpeed: String {
        guard let s = speed else { return "—" }
        return unit.speed(fromMPS: s).formatted(.number.precision(.fractionLength(1)))
    }

    private var displayAvg: String {
        unit.speed(fromMPS: averageSpeed).formatted(.number.precision(.fractionLength(1)))
    }

    private var displayMax: String {
        unit.speed(fromMPS: maxSpeed).formatted(.number.precision(.fractionLength(1)))
    }

    private var displayDistance: String {
        unit.distance(fromMeters: distance).formatted(.number.precision(.fractionLength(1)))
    }

    private enum Trend: Equatable { case up, even, down }

    /// Minimum delta from the ride average before the trend chevron points
    /// up/down. Compared in canonical m/s (≈0.5 km/h) so sensitivity is
    /// identical regardless of the display unit.
    private static let trendThresholdMPS = 0.14

    private var trend: Trend {
        guard let s = speed, averageSpeed > 0 else { return .even }
        let diff = s - averageSpeed
        if diff > Self.trendThresholdMPS { return .up }
        if diff < -Self.trendThresholdMPS { return .down }
        return .even
    }

    private var trendChevron: some View {
        Image(systemName: "chevron.forward.circle.fill")
            .foregroundStyle(
                trend == .up   ? Color("cyRatingGood") :
                trend == .down ? Color("cyRatingBad")  : Color.secondary
            )
            .rotationEffect(.degrees(trend == .up ? -45 : trend == .down ? 45 : 0))
            .animation(.easeInOut(duration: 0.3), value: trend)
    }

    private func statCell(
        label: String,
        value: String,
        labelFont: Font = .caption,
        showChevron: Bool = false
    ) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(label)
                .font(labelFont)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: Spacing.xs) {
                if showChevron { trendChevron }
                Text(value)
                    .dDINCondensed(size: 34, relativeTo: .largeTitle)
                    .lineLimit(1)
            }
        }
    }

    // Scale the large-hero font proportionally to the available height.
    // Nominal 2×2 slot height is 200pt; 136pt is the `large-hero` spec size.
    private func heroFontSize(for height: CGFloat) -> CGFloat {
        let nominal: CGFloat = 136
        let nominalHeight: CGFloat = 200
        return max(34, nominal * (height / nominalHeight))
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
            .foregroundStyle(Color.cyPrimary.opacity(1))
            LineMark(
                x: .value("t", index),
                y: .value("speed", displaySpeed)
            )
            .foregroundStyle(Color.cyPrimary.opacity(1))
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
