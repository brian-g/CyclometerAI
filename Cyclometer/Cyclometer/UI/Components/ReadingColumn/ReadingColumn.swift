import SwiftUI

// MARK: - Reading Column

/// One reading on a widget sheet (#494): a small hero over its label, as the dashboard shows
/// numbers. "—" with no reading, and no unit. VoiceOver reads it as one element, "label, spoken
/// value". Lay several out with `ReadingColumns`.
struct ReadingColumn<Accessory: View>: View {
    let label: String
    let readings: [MetricReading]
    let spoken: String
    let accessory: Accessory

    /// `accessory` sits before the value, centred on its digits (e.g. the heart-rate zone's dot).
    init(_ label: String, _ reading: MetricReading, @ViewBuilder accessory: () -> Accessory) {
        self.label = label
        self.readings = [reading]
        self.spoken = reading.spoken
        self.accessory = accessory()
    }

    init(_ label: String, _ reading: MetricReading) where Accessory == EmptyView {
        self.init(label, reading) { EmptyView() }
    }

    /// Readings of one kind read together, each with its unit: "+9 % / -8 %". A single "—" when
    /// none has a value; `spoken` tells VoiceOver which is which.
    init(_ label: String, _ readings: [MetricReading], spoken: String) where Accessory == EmptyView {
        self.label = label
        self.readings = readings.allSatisfy { $0 == .missing } ? [.missing] : readings
        self.spoken = spoken
        self.accessory = EmptyView()
    }

    var body: some View {
        // The label sits over the readings, not in the first hero, so it doesn't widen that one.
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.caption).heroLabel()
            HStack(alignment: .lastTextBaseline, spacing: Spacing.xs) {
                first
                ForEach(Array(readings.dropFirst().enumerated()), id: \.offset) { _, reading in
                    // A separator, not a number: set as small as the units, on the digits' baseline.
                    Text(verbatim: "/").heroUnit()
                    HeroNumber(reading.value, unit: reading.unit).heroNumberSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(spoken)
    }

    /// The first reading, which carries any accessory. An empty one takes no room, as the Zone
    /// column's absent dot doesn't.
    private var first: HeroNumber<EmptyView> {
        let reading = readings[0]
        return HeroNumber(reading.value, unit: reading.unit)
            .heroNumberSize(.small)
            .heroAccessory(.capCenter) { accessory }
    }
}

// MARK: - Reading Columns

/// A row of `ReadingColumn`s sharing its width equally (#494). Columns that don't fit side by side
/// at their natural width wrap onto another line, rather than wrapping their labels, and keep the
/// same column grid there, so wrapped readings line up under those above. `maxColumns` caps the
/// grid, so more readings than that run on in rows of that many (S15's Elevation, #548).
struct ReadingColumns: Layout {
    var spacing: CGFloat = Spacing.md
    var maxColumns = Int.max

    /// How many columns of `widths` fit across `width`: as many as the widest allows, at least one,
    /// and no more than `maxColumns`.
    static func columns(fitting width: CGFloat, widths: [CGFloat], spacing: CGFloat, maxColumns: Int = .max) -> Int {
        guard let widest = widths.max() else { return 0 }
        let fit = ((width + spacing) / (widest + spacing)).rounded(.down)
        let most = min(widths.count, max(maxColumns, 1))
        // Clamped before `Int(_:)`, which traps on the infinite width a stack proposes to measure
        // its children's flexibility.
        return fit.isNaN ? 1 : Int(min(max(fit, 1), CGFloat(most)))
    }

    private struct Grid {
        let width: CGFloat
        let columns: Int
        let columnWidth: CGFloat
        let rowHeights: [CGFloat]
    }

    /// `width` nil lays the readings out side by side, each column as wide as the widest. Fitting
    /// them to their summed width instead stacked any two of unequal width.
    private func grid(width proposed: CGFloat?, subviews: Subviews) -> Grid {
        let widths = subviews.map { $0.sizeThatFits(.unspecified).width }
        // No width: as many as an unbounded one fits, all of them up to `maxColumns`.
        let columns = Self.columns(fitting: proposed ?? .infinity, widths: widths, spacing: spacing, maxColumns: maxColumns)
        let gaps = spacing * CGFloat(max(columns - 1, 0))
        let width = proposed ?? (widths.max() ?? 0) * CGFloat(columns) + gaps
        let columnWidth = columns == 0 ? 0 : (width - gaps) / CGFloat(columns)
        let proposal = ProposedViewSize(width: columnWidth, height: nil)
        let rowHeights = stride(from: 0, to: subviews.count, by: max(columns, 1)).map { start in
            subviews[start..<min(start + columns, subviews.count)]
                .map { $0.sizeThatFits(proposal).height }
                .max() ?? 0
        }
        return Grid(width: width, columns: columns, columnWidth: columnWidth, rowHeights: rowHeights)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let grid = grid(width: proposal.width, subviews: subviews)
        let height = grid.rowHeights.reduce(0, +) + spacing * CGFloat(max(grid.rowHeights.count - 1, 0))
        return CGSize(width: grid.width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // As `sizeThatFits` measured: with no width proposed, side by side, rather than refitting
        // to a width summed from the readings', which float error can leave a hair short.
        let grid = grid(width: proposal.width == nil ? nil : bounds.width, subviews: subviews)
        let proposal = ProposedViewSize(width: grid.columnWidth, height: nil)
        var y = bounds.minY
        for (row, height) in grid.rowHeights.enumerated() {
            for column in 0..<grid.columns {
                let index = row * grid.columns + column
                guard index < subviews.count else { break }
                let x = bounds.minX + CGFloat(column) * (grid.columnWidth + spacing)
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: proposal)
            }
            y += height + spacing
        }
    }
}

// MARK: - Previews

private let previewSpeed = MetricReading(value: "28.4", unit: "km/h", spoken: "28.4 kilometers per hour")
private let previewTime = MetricReading(value: "1:02:33", spoken: "1 hour, 2 minutes, 33 seconds")
private let previewGrade = MetricReading(value: "+4", unit: "%", spoken: "4 percent")

private struct ReadingColumnsPreview: View {
    var body: some View {
        List {
            Section("One") {
                ReadingColumns { ReadingColumn("Distance", MetricReading(value: "12.3", unit: "km", spoken: "12.3 kilometers")) }
            }
            Section("Two") {
                ReadingColumns {
                    ReadingColumn("Moving Time", previewTime)
                    ReadingColumn("Ride Time", previewTime)
                }
            }
            Section("Three") {
                ReadingColumns {
                    ReadingColumn("Current", previewSpeed)
                    ReadingColumn("Average", previewSpeed)
                    ReadingColumn("Max", .missing)
                }
            }
            Section("Pair") {
                ReadingColumns {
                    ReadingColumn("Current", previewGrade)
                    ReadingColumn(
                        "Steepest",
                        [MetricReading(value: "+9", unit: "%", spoken: "9 percent"), MetricReading(value: "-8", unit: "%", spoken: "-8 percent")],
                        spoken: "climb 9 percent, descent -8 percent"
                    )
                }
            }
            Section("Two at Most") {
                ReadingColumns(maxColumns: 2) {
                    ReadingColumn("Highest", previewGrade)
                    ReadingColumn("Lowest", previewGrade)
                    ReadingColumn("Ascent", previewGrade)
                    ReadingColumn("Descent", previewGrade)
                    ReadingColumn("Steepest", previewGrade)
                }
            }
            Section("Wrapping") {
                ReadingColumns {
                    ReadingColumn("Moving Time", previewTime)
                    ReadingColumn("Stopped Time", previewTime)
                    ReadingColumn("Paused Time", previewTime)
                    ReadingColumn("Ride Time", previewTime)
                }
            }
            Section("Accessory") {
                ReadingColumns {
                    ReadingColumn("Heart Rate", MetricReading(value: "156", unit: "bpm", spoken: "156 beats per minute"))
                    ReadingColumn("Zone", MetricReading(value: "3", spoken: "Zone 3, Aerobic")) {
                        ZoneDot(color: .hrZone(3))
                    }
                }
            }
        }
    }
}

#Preview("Columns") {
    ReadingColumnsPreview()
}

#Preview("Columns — Dark") {
    ReadingColumnsPreview()
        .preferredColorScheme(.dark)
}

#Preview("Columns — Large Text") {
    ReadingColumnsPreview()
        .dynamicTypeSize(.accessibility3)
}
