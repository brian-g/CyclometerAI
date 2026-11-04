import SwiftUI

// MARK: - W1 Speed Gauge Widget (option B)

/// W1 Speed, option B (#534), per `W1 - Speed (2x2) option b` in Design.sketch: the speed on a
/// 270° gauge, with the ride average and max as ticks on its arc, over W2's chart. Average, max,
/// distance and time sit in the four corners.
struct SpeedGaugeWidget: View {
    let speed: Double?                  // m/s; nil → "—"
    let speedHistory: [SpeedSample]     // W2's speed watermark
    let averageHistory: [SpeedSample]   // W2's average line, over the same window
    let distance: Double                // meters
    let elapsed: Int                    // seconds
    let averageSpeed: Double            // m/s
    let maxSpeed: Double                // m/s
    var unit: UnitSystem = .metric
    /// The Ride Metrics sheet's data. A closure so the card never reads it; only the open sheet does,
    /// in its own body (#144).
    var metrics: () -> RideMetrics = { RideMetrics() }

    /// The chart fills the lower part of the cell, as drawn (Sketch: 104 of 195 pt).
    private static let chartHeightFraction: CGFloat = 0.55

    var body: some View {
        ZStack {
            if !speedHistory.isEmpty || !averageHistory.isEmpty {
                GeometryReader { geo in
                    AverageSpeedHistoryChart(speedHistory: speedHistory, averageHistory: averageHistory, unit: unit)
                        .frame(height: geo.size.height * Self.chartHeightFraction)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        // A line at the top of the range strokes past the frame (see W2).
                        .clipped()
                }
            }
            gauge
                .padding(.vertical, Spacing.sm)
            corners
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cyBgSecondary)
        .widgetDetail(label: SpeedGaugeDashboardWidget.title, value: accessibilityValue) {
            RideMetricsSheet(metrics: metrics)
        }
    }

    // MARK: - Sub-Views

    private var gauge: some View {
        let top = SpeedGaugeScale.top(maxSpeedMPS: maxSpeed, unit: unit)
        return SpeedGaugeDial(
            speedFraction: speed.map { SpeedGaugeScale.fraction(ofMPS: $0, top: top, unit: unit) } ?? 0,
            averageFraction: averageSpeed > 0 ? SpeedGaugeScale.fraction(ofMPS: averageSpeed, top: top, unit: unit) : nil,
            maxFraction: maxSpeed > 0 ? SpeedGaugeScale.fraction(ofMPS: maxSpeed, top: top, unit: unit) : nil,
            tickFractions: SpeedGaugeScale.ticks(top: top).map { $0 / top }
        ) {
            HeroNumber(displaySpeed, unit: speed == nil ? "" : unit.speedLabel)
                .heroTrend(.speed(speed, against: averageSpeed))
        }
    }

    private var corners: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                HeroNumber(displayAvg, unit: "avg").heroNumberSize(.small)
                Spacer(minLength: 0)
                HeroNumber(displayMax, unit: "max").heroNumberSize(.small)
            }
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline) {
                HeroNumber(displayDistance, unit: unit.distanceLabel).heroNumberSize(.small)
                Spacer(minLength: 0)
                HeroNumber(elapsed.formattedElapsed, unit: "").heroNumberSize(.small)
            }
        }
    }

    // MARK: - Computed Display Values

    private func oneDecimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    private var displaySpeed: String {
        speed.map { oneDecimal(unit.speed(fromMPS: $0)) } ?? "—"
    }

    private var displayAvg: String { oneDecimal(unit.speed(fromMPS: averageSpeed)) }
    private var displayMax: String { oneDecimal(unit.speed(fromMPS: maxSpeed)) }
    private var displayDistance: String { oneDecimal(unit.distance(fromMeters: distance)) }

    /// What VoiceOver reads after the title (#361): W1's 2×2 reading, with no "—" read aloud.
    var accessibilityValue: String {
        var parts = [speed.map(unit.spokenSpeed(fromMPS:)) ?? "No reading"]
        if let trend = Trend.speed(speed, against: averageSpeed).spokenAgainstAverage { parts.append(trend) }
        parts += [
            "average \(displayAvg)", "maximum \(displayMax)",
            "distance \(unit.spokenDistance(fromMeters: distance))", "time \(elapsed.spokenElapsed)",
        ]
        return parts.joined(separator: ", ")
    }
}

// MARK: - Scale

/// The gauge's scale (#534): 0–60 km/h or 0–40 mph, a tick every 5. Once the ride's max passes the
/// top, the top grows to the next 10. The max only rises during a ride, so the scale never shrinks
/// back.
enum SpeedGaugeScale {
    static let tickStep: Double = 5
    static let growthStep: Double = 10

    /// The top of the scale before the ride's max passes it, in display units.
    static func baseTop(_ unit: UnitSystem) -> Double {
        switch unit {
        case .metric: 60
        case .imperial: 40
        }
    }

    /// The top of the scale, in display units. Taken from the max as the corner shows it, to one
    /// decimal, so a max that reads 60.0 doesn't grow the scale.
    static func top(maxSpeedMPS: Double, unit: UnitSystem) -> Double {
        let max = (unit.speed(fromMPS: maxSpeedMPS) * 10).rounded() / 10
        return Swift.max(baseTop(unit), (max / growthStep).rounded(.up) * growthStep)
    }

    /// How far along the arc `mps` sits, 0…1.
    static func fraction(ofMPS mps: Double, top: Double, unit: UnitSystem) -> Double {
        min(max(unit.speed(fromMPS: mps) / top, 0), 1)
    }

    /// The scale's ticks, in display units: every `tickStep` between the ends, which the arc's
    /// own ends already mark.
    static func ticks(top: Double) -> [Double] {
        Array(stride(from: tickStep, to: top, by: tickStep))
    }
}

// MARK: - Dial

/// The arc, its ticks and markers, with `center` (the speed) in the middle of the circle.
private struct SpeedGaugeDial<Center: View>: View {
    let speedFraction: Double
    let averageFraction: Double?
    let maxFraction: Double?
    let tickFractions: [Double]
    @ViewBuilder let center: Center

    // Proportions of the arc's outer radius, from the Sketch gauge image (radius ≈ 97 pt).
    private static var strokeToRadius: CGFloat { 0.16 }
    private static var tickGapToRadius: CGFloat { 0.06 }
    private static var tickLengthToRadius: CGFloat { 0.07 }
    /// How far the average and max ticks reach past both edges of the arc.
    private static var markerOverhangToRadius: CGFloat { 0.05 }
    private static var markerWidth: CGFloat { 3 }
    /// The gauge's widest share of the cell, so the corners keep their room (Sketch: 212 of 402 pt).
    private static var widthFraction: CGFloat { 0.53 }

    /// 270°, open at the bottom: from 7:30 clockwise to 4:30.
    private static var startDegrees: Double { 135 }
    private static var sweepDegrees: Double { 270 }

    /// The arc's height over its radius: the top of the circle down to the arc's ends, 45° below
    /// the centre.
    private static var heightToRadius: CGFloat { 1 + sin(.pi / 4) }

    var body: some View {
        GeometryReader { geo in
            // The markers reach past the circle at the top and sides.
            let reach = 1 + Self.markerOverhangToRadius
            let radius = min(
                geo.size.height / (Self.heightToRadius + Self.markerOverhangToRadius),
                geo.size.width * Self.widthFraction / 2 / reach
            )
            let dialHeight = radius * (Self.heightToRadius + Self.markerOverhangToRadius)
            let centerPoint = CGPoint(
                x: geo.size.width / 2,
                y: (geo.size.height - dialHeight) / 2 + radius * reach
            )
            ZStack {
                Canvas { context, _ in draw(in: &context, center: centerPoint, radius: radius) }
                center
                    .frame(maxWidth: 2 * radius * (1 - Self.strokeToRadius))
                    .minimumScaleFactor(0.5)
                    .position(centerPoint)
            }
        }
    }

    private func draw(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        let stroke = radius * Self.strokeToRadius
        let arcRadius = radius - stroke / 2

        func arc(to fraction: Double) -> Path {
            Path { path in
                path.addArc(
                    center: center, radius: arcRadius,
                    startAngle: angle(0), endAngle: angle(fraction), clockwise: false
                )
            }
        }

        context.stroke(arc(to: 1), with: .color(.cyBgTertiary), lineWidth: stroke)
        if speedFraction > 0 {
            context.stroke(arc(to: speedFraction), with: .color(.cyPrimary), lineWidth: stroke)
        }

        let tickOuter = radius - stroke - radius * Self.tickGapToRadius
        for fraction in tickFractions {
            context.stroke(
                radial(at: fraction, from: tickOuter - radius * Self.tickLengthToRadius, to: tickOuter, center: center),
                with: .color(.cyTextTertiary), lineWidth: Spacing.strokeThin
            )
        }

        let overhang = radius * Self.markerOverhangToRadius
        // Max under average, so a ride at a steady speed still shows its average.
        for (fraction, color) in [(maxFraction, Color.cyRatingOkay), (averageFraction, Color.cyTextPrimary)] {
            guard let fraction else { continue }
            context.stroke(
                radial(at: fraction, from: radius - stroke - overhang, to: radius + overhang, center: center),
                with: .color(color), lineWidth: Self.markerWidth
            )
        }
    }

    private func angle(_ fraction: Double) -> Angle {
        .degrees(Self.startDegrees + Self.sweepDegrees * fraction)
    }

    /// A line along the radius at `fraction` of the arc, from `inner` to `outer` from the centre.
    private func radial(at fraction: Double, from inner: CGFloat, to outer: CGFloat, center: CGPoint) -> Path {
        let radians = angle(fraction).radians
        let direction = CGPoint(x: cos(radians), y: sin(radians))
        return Path { path in
            path.move(to: CGPoint(x: center.x + direction.x * inner, y: center.y + direction.y * inner))
            path.addLine(to: CGPoint(x: center.x + direction.x * outer, y: center.y + direction.y * outer))
        }
    }
}

// MARK: - Previews

#Preview("Active") {
    SpeedGaugeWidget(
        speed: 9.2,
        speedHistory: SpeedSample.sampleHour,
        averageHistory: SpeedSample.sampleHourAverage,
        distance: 12_300,
        elapsed: 2_340,
        averageSpeed: 7.89,
        maxSpeed: 13.4,
        unit: .metric
    )
    .frame(width: 402, height: 250)
}

#Preview("Imperial — Dark") {
    SpeedGaugeWidget(
        speed: 6.5,
        speedHistory: SpeedSample.sampleHour,
        averageHistory: SpeedSample.sampleHourAverage,
        distance: 22_370,
        elapsed: 30_874,
        averageSpeed: 7.89,
        maxSpeed: 13.4,
        unit: .imperial
    )
    .frame(width: 402, height: 250)
    .preferredColorScheme(.dark)
}

#Preview("Past the scale") {
    // 72 km/h max: the scale grows to 80.
    SpeedGaugeWidget(
        speed: 19.4,
        speedHistory: SpeedSample.sampleHour,
        averageHistory: SpeedSample.sampleHourAverage,
        distance: 41_800,
        elapsed: 5_420,
        averageSpeed: 8.6,
        maxSpeed: 20,
        unit: .metric
    )
    .frame(width: 402, height: 250)
}

#Preview("No reading") {
    SpeedGaugeWidget(
        speed: nil,
        speedHistory: [],
        averageHistory: [],
        distance: 0,
        elapsed: 0,
        averageSpeed: 0,
        maxSpeed: 0
    )
    .frame(width: 402, height: 250)
}

#Preview("Top row") {
    // Page row 1: the Dynamic Island's inset leaves the cell as tall as the Sketch artboard.
    SpeedGaugeWidget(
        speed: 5.6,
        speedHistory: SpeedSample.sampleHour,
        averageHistory: SpeedSample.sampleHourAverage,
        distance: 22_370,
        elapsed: 2_340,
        averageSpeed: 6.2,
        maxSpeed: 6.2,
        unit: .imperial
    )
    .frame(width: 402, height: 195)
}
