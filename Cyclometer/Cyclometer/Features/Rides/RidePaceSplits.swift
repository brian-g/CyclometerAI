import SwiftUI

// MARK: - Pace Split

/// One mile (or kilometre) of a finished ride (#547) and the moving time it took. The last split
/// of a ride is usually partial; its pace is scaled to a whole unit.
struct PaceSplit: Equatable, Sendable {
    /// 1-based.
    var index: Int
    var meters: Double
    var movingSeconds: Double
    var isPartial = false

    /// "3", or the partial split's distance, "0.4".
    func label(_ unit: UnitSystem) -> String {
        isPartial ? unit.distance(fromMeters: meters).formatted(.number.precision(.fractionLength(1))) : "\(index)"
    }

    /// "Mile 3", or "Final 0.4 miles".
    func spokenLabel(_ unit: UnitSystem) -> String {
        isPartial ? "Final \(unit.spokenDistance(fromMeters: meters))" : "\(unit == .metric ? "Kilometer" : "Mile") \(index)"
    }

    func pace(_ unit: UnitSystem) -> MetricReading {
        let mps = meters / movingSeconds
        guard let shown = unit.formattedPace(fromMPS: mps), let spoken = unit.spokenPace(fromMPS: mps) else { return .missing }
        return MetricReading(value: shown, unit: unit.paceLabel, spoken: spoken)
    }
}

// MARK: - Pace Splits

enum PaceSplits {
    /// A leftover shorter than this reads "0.0" at the label's one decimal, so it isn't a split.
    static let minimumPartialDistance = 0.05

    /// Metres in one of `unit`'s distance units: a mile or a kilometre.
    static func metersPerSplit(_ unit: UnitSystem) -> Double {
        1 / unit.distance(fromMeters: 1)
    }

    /// The ride's splits every `metersPerSplit`, on moving time. Replays the tick's rule, as
    /// `WatermarkSeed` does: a point above `stationarySpeedMPS` covers its speed in metres in one
    /// moving second, so the splits add up to the odometer's distance and the Moving Time, and
    /// average to the Average pace. A second that crosses a boundary is shared between the two
    /// splits in proportion. Pauses leave no points, so they add nothing.
    ///
    /// Empty for a ride shorter than one whole split. A partial last split is kept unless it rounds
    /// to nothing (`minimumPartialDistance`).
    static func splits(_ points: [TrackPointDTO], metersPerSplit: Double) -> [PaceSplit] {
        guard metersPerSplit > 0 else { return [] }
        var splits: [PaceSplit] = []
        var meters = 0.0, seconds = 0.0
        for point in points {
            guard let mps = point.speedMPS, mps > ActiveRideFeature.stationarySpeedMPS else { continue }
            var secondLeft = 1.0
            while meters + mps * secondLeft >= metersPerSplit {
                let needed = (metersPerSplit - meters) / mps
                seconds += needed
                secondLeft -= needed
                splits.append(PaceSplit(index: splits.count + 1, meters: metersPerSplit, movingSeconds: seconds))
                meters = 0
                seconds = 0
            }
            meters += mps * secondLeft
            seconds += secondLeft
        }
        guard !splits.isEmpty else { return [] }
        if meters / metersPerSplit >= minimumPartialDistance {
            splits.append(PaceSplit(index: splits.count + 1, meters: meters, movingSeconds: seconds, isPartial: true))
        }
        return splits
    }
}

// MARK: - Pace Split Rows

/// S15's splits table in the Pace section (#547): a column header, the first
/// `collapsedSplitCount` splits, then "More" disclosing the rest.
struct PaceSplitRows: View {
    let splits: [PaceSplit]
    let unit: UnitSystem
    @State private var isExpanded: Bool

    static let collapsedSplitCount = 5

    init(splits: [PaceSplit], unit: UnitSystem, isExpanded: Bool = false) {
        self.splits = splits
        self.unit = unit
        _isExpanded = State(initialValue: isExpanded)
    }

    var body: some View {
        HStack {
            Text(unit.distanceLabel)
            Spacer(minLength: Spacing.sm)
            Text("Pace")
        }
        .font(.caption)
        .heroLabel()
        .foregroundStyle(Color.cyTextSecondary)
        .accessibilityHidden(true)
        ForEach(splits.prefix(Self.collapsedSplitCount), id: \.index) { PaceSplitRow(split: $0, unit: unit) }
        if splits.count > Self.collapsedSplitCount {
            DisclosureGroup("More", isExpanded: $isExpanded) {
                ForEach(splits.dropFirst(Self.collapsedSplitCount), id: \.index) { PaceSplitRow(split: $0, unit: unit) }
            }
        }
    }
}

private struct PaceSplitRow: View {
    let split: PaceSplit
    let unit: UnitSystem

    var body: some View {
        let pace = split.pace(unit)
        HStack(alignment: .firstTextBaseline) {
            Text(split.label(unit))
            Spacer(minLength: Spacing.sm)
            Text("\(Text(pace.value)) \(Text(pace.unit).font(.footnote).foregroundStyle(Color.cyTextSecondary))")
        }
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(split.spokenLabel(unit))
        .accessibilityValue(pace.spoken)
    }
}

// MARK: - Previews

extension PaceSplit {
    /// `count` whole splits of `unit`, at paces rolling around ~4 min/mi or ~2:30 min/km, and a
    /// partial last split of `partial` units.
    static func samples(_ count: Int, partial: Double = 0.4, unit: UnitSystem = .imperial) -> [PaceSplit] {
        let meters = PaceSplits.metersPerSplit(unit)
        var splits = (1...count).map { index in
            PaceSplit(index: index, meters: meters,
                      movingSeconds: (unit == .imperial ? 240 : 150) * (1 + 0.15 * sin(Double(index))))
        }
        if partial > 0 {
            splits.append(PaceSplit(index: count + 1, meters: meters * partial,
                                    movingSeconds: (unit == .imperial ? 250 : 155) * partial, isPartial: true))
        }
        return splits
    }
}

#Preview("Five splits, no More") {
    List { Section("Pace") { PaceSplitRows(splits: PaceSplit.samples(4), unit: .imperial) } }
}

#Preview("Twelve splits — collapsed") {
    List { Section("Pace") { PaceSplitRows(splits: PaceSplit.samples(12), unit: .imperial) } }
}

#Preview("Twelve splits — expanded") {
    List { Section("Pace") { PaceSplitRows(splits: PaceSplit.samples(12), unit: .imperial, isExpanded: true) } }
}

#Preview("Metric — Dark") {
    List { Section("Pace") { PaceSplitRows(splits: PaceSplit.samples(20, unit: .metric), unit: .metric) } }
        .preferredColorScheme(.dark)
}
