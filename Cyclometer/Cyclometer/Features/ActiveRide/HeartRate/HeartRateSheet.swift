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
    /// The Heart Rate sheet's inputs: W4/W12's reading, and zones resolved the way S12 and S10
    /// resolve them.
    var heartRateMetrics: HeartRateMetrics {
        let bounds = HeartRateZone.allCases.map {
            riderProfile.bounds(for: $0, healthResting: healthRestingBPM, healthMax: healthMaxBPM,
                                healthZoneCeilings: healthZoneCeilingsBPM)
        }
        return HeartRateMetrics(
            bpm: displayHeartRateBPM,
            zone: displayHRZone,
            source: hrSource,
            zoneBounds: bounds,
            zoneSeconds: RideDetailSeries.zoneSeconds(hrSecondsTally.secondsByBPM, zoneBounds: bounds)
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

    private static let donutHeight: CGFloat = 120

    var body: some View {
        let zoneRows = metrics.zoneRows
        List {
            Section {
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

// MARK: - Previews

extension HeartRateMetrics {
    /// A strap reading 156 bpm in zone 3 (151–163), 39 minutes in, against the default profile.
    static let sample = HeartRateMetrics(
        bpm: 156,
        zone: 3,
        source: .bleStrap,
        zoneSeconds: [312, 846, 702, 318, 42]
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
