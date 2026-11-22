import SwiftUI

/// S15's Summary (UX.md §S15): the whole ride at a glance in hero numbers, each left out when the
/// ride recorded nothing for it (#460), then the vehicle pass count (#549). Average Power waits
/// for Phase 3.
///
/// S10 shows the same section (#645), led by the ride's distance and time, which S15 shows in its
/// title block instead. Store-free so both screens draw it, and generic over the passes row: S15's
/// opens the passes sheet, S10 has none.
struct RideSummarySection<PassesRow: View>: View {
    /// Nil until loaded, or when the read failed: then only `leading` shows.
    let stats: RideStats?
    let unit: UnitSystem
    /// Readings ahead of S15's, S10's Distance and Time (#645).
    var leading: [SummaryReading] = []
    @ViewBuilder let passesRow: (Int) -> PassesRow

    var body: some View {
        let readings = leading + (stats?.summaryReadings(unit) ?? [])
        let passes = stats?.vehiclePassCount
        if !readings.isEmpty || passes != nil {
            Section("Summary") {
                if !readings.isEmpty {
                    ReadingColumns {
                        ForEach(readings, id: \.label) { item in
                            ReadingColumn(item.label, item.reading)
                        }
                    }
                }
                // Absent with no radar paired, where "0 passes" would be a claim nobody measured.
                if let passes {
                    passesRow(passes)
                }
            }
        }
    }
}

/// One hero in the Summary: its label over its reading.
struct SummaryReading: Equatable {
    let label: String
    let reading: MetricReading
}

/// S15's Summary values, each nil when the ride recorded nothing for it, so it is left out rather
/// than dashed (UX.md §S15, #460).
extension RideStats {
    /// The Summary's readings in order, those the ride recorded nothing for left out.
    func summaryReadings(_ unit: UnitSystem) -> [SummaryReading] {
        [
            ascent(unit).map { SummaryReading(label: "Ascent", reading: $0) },
            descent(unit).map { SummaryReading(label: "Descent", reading: $0) },
            averageSpeed(unit).map { SummaryReading(label: "Avg Speed", reading: $0) },
            averageHeartRate.map { SummaryReading(label: "Avg Heart Rate", reading: $0) },
            averageCadence.map { SummaryReading(label: "Avg Cadence", reading: $0) },
            calories.map { SummaryReading(label: "Calories", reading: $0) },
        ].compactMap { $0 }
    }

    func ascent(_ unit: UnitSystem) -> MetricReading? {
        ascentMeters.map { Self.elevation($0, unit) }
    }

    func descent(_ unit: UnitSystem) -> MetricReading? {
        descentMeters.map { Self.elevation($0, unit) }
    }

    /// Nil with no moving second, when the stored average is a 0 nobody rode — the Speed
    /// section's rule (`RideMetrics.hasSpeed`).
    func averageSpeed(_ unit: UnitSystem) -> MetricReading? {
        guard movingSeconds > 0 else { return nil }
        return MetricReading(value: unit.speed(fromMPS: averageSpeedMPS).formatted(.number.precision(.fractionLength(1))),
                             unit: unit.speedLabel, spoken: unit.spokenSpeed(fromMPS: averageSpeedMPS))
    }

    var averageHeartRate: MetricReading? { averageHeartRateBPM.map(Self.heartRate) }

    /// Nil with no cadence sensor. A real 0 rpm average is a reading.
    var averageCadence: MetricReading? {
        averageCadenceRPM.map { MetricReading(value: $0.formatted(), unit: "rpm", spoken: "\($0) rpm") }
    }

    var calories: MetricReading? {
        activeKilocalories.map {
            MetricReading(value: CaloriesMetrics.whole($0), unit: "kcal", spoken: CaloriesMetrics.spoken($0))
        }
    }

    private static func elevation(_ meters: Double, _ unit: UnitSystem) -> MetricReading {
        MetricReading(value: unit.elevation(fromMeters: meters).formatted(.number.precision(.fractionLength(0))),
                      unit: unit.elevationLabel, spoken: unit.spokenElevation(fromMeters: meters))
    }

    private static func heartRate(_ bpm: Int) -> MetricReading {
        MetricReading(value: bpm.formatted(), unit: "bpm", spoken: "\(bpm) beats per minute")
    }
}

// MARK: - Previews

private let previewStats = RideStats(
    averageSpeedMPS: 7.2, maxSpeedMPS: 12.4, averageCadenceRPM: 88, vehiclePassCount: 14,
    averageHeartRateBPM: 142, ascentMeters: 412, descentMeters: 398, activeKilocalories: 845,
    movingSeconds: 7_100
)

#Preview("All readings") {
    List {
        RideSummarySection(stats: previewStats, unit: .imperial) { passes in
            LabeledContent("Vehicle Passes", value: passes.formatted())
        }
    }
}

#Preview("GPS only, metric") {
    List {
        RideSummarySection(stats: RideStats(averageSpeedMPS: 7.2, maxSpeedMPS: 12.4, ascentMeters: 412,
                                            descentMeters: 398, movingSeconds: 7_100),
                           unit: .metric) { passes in
            LabeledContent("Vehicle Passes", value: passes.formatted())
        }
    }
}
