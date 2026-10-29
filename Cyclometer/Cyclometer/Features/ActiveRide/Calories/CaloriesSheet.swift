import Charts
import SwiftUI

// MARK: - Calories

/// What the Calories sheet shows (#465): W23's series, which model the estimate came from, and the
/// average burn over W3's moving time.
struct CaloriesMetrics: Equatable {
    var rider: EnergyRiderStatus = .loading
    var series: [CaloriePoint] = []
    /// W1's Time: recording seconds, where the chart's ride-time axis ends.
    var rideSeconds: Int = 0

    var latest: CaloriePoint? { series.last }

    var total: MetricReading {
        guard let latest else { return .missing }
        return MetricReading(shown: "\(Self.whole(latest.kilocalories)) kcal", spoken: Self.spoken(latest.kilocalories))
    }

    var model: MetricReading {
        guard let method = latest?.method else { return .missing }
        let name = switch method {
        case .heartRate: "Heart rate"
        case .physics: "Physics"
        case .met: "MET"
        }
        return MetricReading(shown: name, spoken: name)
    }

    /// kcal per hour of W3's moving time, both as of the latest estimate.
    var averagePerHour: Double? {
        latest.flatMap { CalorieSeries.kilocaloriesPerHour($0.kilocalories, movingSeconds: $0.movingSeconds) }
    }

    var average: MetricReading {
        guard let averagePerHour else { return .missing }
        return MetricReading(shown: "\(Self.whole(averagePerHour)) kcal/h", spoken: "\(Self.spoken(averagePerHour)) per hour")
    }

    /// Why there is no estimate, or nil with one.
    var emptyReason: String? {
        guard latest == nil else { return nil }
        return rider == .noBodyMass
            ? "Add your weight in the Health app to estimate active calories."
            : "The first estimate comes after a minute of riding."
    }

    /// Under the stats: which model the estimate came from, or why there is none.
    var footer: String {
        emptyReason ?? "Model: \(model.shown)"
    }

    static func whole(_ kilocalories: Double) -> String {
        kilocalories.formatted(.number.precision(.fractionLength(0)))
    }

    /// "412 kilocalories", as the other rows' units are read (#361).
    static func spoken(_ kilocalories: Double) -> String {
        Measurement(value: kilocalories, unit: UnitEnergy.kilocalories).formatted(.measurement(
            width: .wide, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))
        ))
    }
}

extension ActiveRideFeature.State {
    /// The Calories sheet's inputs.
    var caloriesMetrics: CaloriesMetrics {
        CaloriesMetrics(rider: energyRider, series: calories, rideSeconds: elapsedSeconds)
    }
}

// MARK: - Calories Sheet

/// The Calories sheet, W23's (#465).
///
/// `metrics` is called in this view's own `body`, not the presenter's `.sheet` builder, so the
/// open sheet follows the ride (see `RideMetricsSheet`, #144).
struct CaloriesSheet: View {
    var metrics: () -> CaloriesMetrics = { CaloriesMetrics() }

    @Environment(\.dismiss) private var dismiss
    @State private var detent = PresentationDetent.medium

    var body: some View {
        let metrics = metrics()
        NavigationStack {
            CaloriesList(metrics: metrics)
                .navigationTitle("Active Calories")
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

/// The sheet's chart and stats, apart from its navigation chrome so a snapshot can pin them.
struct CaloriesList: View {
    let metrics: CaloriesMetrics

    private static let chartHeight: CGFloat = 140

    var body: some View {
        List {
            Section {
                if !metrics.series.isEmpty {
                    CaloriesChart(series: metrics.series, rideSeconds: metrics.rideSeconds)
                        .frame(height: Self.chartHeight)
                }
                HStack(alignment: .top, spacing: Spacing.md) {
                    stat("Total", metrics.latest?.kilocalories, unit: "kcal", metrics.total)
                    stat("Average", metrics.averagePerHour, unit: "kcal/h", metrics.average)
                }
            } footer: {
                Text(metrics.footer)
            }
        }
    }

    /// One column: a small hero over its label, "—" with no estimate.
    private func stat(_ label: String, _ value: Double?, unit: String, _ reading: MetricReading) -> some View {
        HeroNumber(value.map(CaloriesMetrics.whole) ?? "—", unit: value == nil ? "" : unit) {
            Text(label).font(.caption)
        }
        .heroNumberSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(reading.spoken)
    }
}

// MARK: - Calories Chart

/// Active calories accumulating over ride time, from zero at the start to now. Ride time, not the
/// clock: a pause takes no room, as it adds nothing.
private struct CaloriesChart: View {
    let series: [CaloriePoint]
    let rideSeconds: Int

    private struct Point: Identifiable {
        let seconds: Int
        let kilocalories: Double
        var id: Int { seconds }
    }

    var body: some View {
        let points = [Point(seconds: 0, kilocalories: 0)]
            + series.map { Point(seconds: $0.rideSeconds, kilocalories: $0.kilocalories) }
        let end = max(rideSeconds, series.last?.rideSeconds ?? 0)
        Chart(points) { point in
            AreaMark(x: .value("t", point.seconds), y: .value("kcal", point.kilocalories))
                .foregroundStyle(Color.cyPrimary.opacity(Opacity.watermark))
            LineMark(x: .value("t", point.seconds), y: .value("kcal", point.kilocalories))
                .foregroundStyle(Color.cyPrimary)
        }
        .chartXScale(domain: 0...end)
        .chartXAxis {
            AxisMarks(values: Self.ticks(through: end)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let seconds = value.as(Int.self) {
                        Text(Duration.seconds(seconds).formatted(.time(pattern: .hourMinute(padHourToLength: 1))))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let kilocalories = value.as(Double.self) {
                        Text("\(CaloriesMetrics.whole(kilocalories)) kcal")
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .accessibilityLabel("Active calories over ride time")
    }

    /// Ticks on whole minutes, at the first step from one minute to two hours that gives no more
    /// than five: "0:00", "0:15", "0:30"…
    static func ticks(through seconds: Int) -> [Int] {
        let minutes = [1, 2, 5, 10, 15, 30, 60, 120]
        let step = (minutes.first { seconds / ($0 * 60) < 5 } ?? minutes[minutes.count - 1]) * 60
        return Array(stride(from: 0, through: seconds, by: step))
    }
}

// MARK: - Previews

extension CaloriesMetrics {
    /// Three minutes in, before heart rate could cover half the ride: physics.
    static let sampleEarly = CaloriesMetrics(
        rider: .rider(RideEnergy.Rider(kilograms: 75)),
        series: [
            CaloriePoint(rideSeconds: 60, movingSeconds: 57, kilocalories: 9, method: .physics),
            CaloriePoint(rideSeconds: 120, movingSeconds: 114, kilocalories: 21, method: .physics),
            CaloriePoint(rideSeconds: 180, movingSeconds: 170, kilocalories: 34, method: .physics),
        ],
        rideSeconds: 205
    )

    /// Three hours in, from heart rate since the 20th minute: the series steps where the strap's
    /// readings first covered half the ride (#465's known behaviour).
    static let sampleLong = CaloriesMetrics(
        rider: .rider(RideEnergy.Rider(kilograms: 75, age: 45, sex: .male)),
        series: (1...180).map { minute in
            // Physics at 7 kcal a minute, then heart rate's whole-ride estimate: 9 a minute, give
            // or take 1.5 over the climbs, so it never falls.
            let t = Double(minute)
            return CaloriePoint(
                rideSeconds: minute * 60,
                movingSeconds: minute * 10_140 / 180,
                kilocalories: minute < 20 ? 7 * t : 9 * t - 22.5 * cos(t / 15),
                method: minute < 20 ? .physics : .heartRate
            )
        },
        rideSeconds: 10_830
    )

    static let sampleNoBodyMass = CaloriesMetrics(rider: .noBodyMass, rideSeconds: 1_260)

    /// Inside the first minute: a rider, but no estimate yet.
    static let sampleNoEstimate = CaloriesMetrics(rider: .rider(RideEnergy.Rider(kilograms: 75)), rideSeconds: 40)
}

#Preview("Long ride") {
    CaloriesList(metrics: .sampleLong)
}

#Preview("Early ride") {
    CaloriesList(metrics: .sampleEarly)
}

#Preview("No body mass") {
    CaloriesList(metrics: .sampleNoBodyMass)
}

#Preview("No estimate yet") {
    CaloriesList(metrics: .sampleNoEstimate)
}

#Preview("Long ride — Dark") {
    CaloriesList(metrics: .sampleLong)
        .preferredColorScheme(.dark)
}

#Preview("Early ride — Dark") {
    CaloriesList(metrics: .sampleEarly)
        .preferredColorScheme(.dark)
}

#Preview("No body mass — Dark") {
    CaloriesList(metrics: .sampleNoBodyMass)
        .preferredColorScheme(.dark)
}

#Preview("No estimate yet — Dark") {
    CaloriesList(metrics: .sampleNoEstimate)
        .preferredColorScheme(.dark)
}
