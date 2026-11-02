import SwiftUI

// MARK: - Reading Column

/// One reading on a widget sheet (#494): a small hero over its label, as the dashboard shows
/// numbers. "—" with no reading, and no unit. VoiceOver reads it as one element, "label, spoken
/// value". Lay several out with `ReadingColumns`.
struct ReadingColumn<Accessory: View>: View {
    let label: String
    let reading: MetricReading
    let accessory: Accessory

    /// `accessory` sits before the value, on its baseline (e.g. the heart-rate zone's dot).
    init(_ label: String, _ reading: MetricReading, @ViewBuilder accessory: () -> Accessory) {
        self.label = label
        self.reading = reading
        self.accessory = accessory()
    }

    init(_ label: String, _ reading: MetricReading) where Accessory == EmptyView {
        self.init(label, reading) { EmptyView() }
    }

    var body: some View {
        hero
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(reading.spoken)
    }

    private var hero: HeroNumber<Text> {
        let hero = HeroNumber(reading.value, unit: reading.unit) { Text(label).font(.caption) }
            .heroNumberSize(.small)
        return Accessory.self == EmptyView.self ? hero : hero.heroAccessory { accessory }
    }
}

// MARK: - Reading Columns

/// A row of `ReadingColumn`s sharing its width equally (#494). Columns that don't fit side by side
/// at their natural width wrap onto another line, rather than wrapping their labels, and keep the
/// same column grid there, so wrapped readings line up under those above.
struct ReadingColumns: Layout {
    var spacing: CGFloat = Spacing.md

    /// How many columns of `widths` fit across `width`: as many as the widest allows, at least one.
    static func columns(fitting width: CGFloat, widths: [CGFloat], spacing: CGFloat) -> Int {
        guard let widest = widths.max() else { return 0 }
        let fit = Int(((width + spacing) / (widest + spacing)).rounded(.down))
        return min(widths.count, max(fit, 1))
    }

    private struct Grid {
        let columns: Int
        let columnWidth: CGFloat
        let rowHeights: [CGFloat]
    }

    private func grid(width: CGFloat, subviews: Subviews) -> Grid {
        let widths = subviews.map { $0.sizeThatFits(.unspecified).width }
        let columns = Self.columns(fitting: width, widths: widths, spacing: spacing)
        let columnWidth = columns == 0 ? 0 : (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let proposal = ProposedViewSize(width: columnWidth, height: nil)
        let rowHeights = stride(from: 0, to: subviews.count, by: max(columns, 1)).map { start in
            subviews[start..<min(start + columns, subviews.count)]
                .map { $0.sizeThatFits(proposal).height }
                .max() ?? 0
        }
        return Grid(columns: columns, columnWidth: columnWidth, rowHeights: rowHeights)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }
        let width = proposal.width ?? (ideal.reduce(0, +) + spacing * CGFloat(max(ideal.count - 1, 0)))
        let grid = grid(width: width, subviews: subviews)
        let height = grid.rowHeights.reduce(0, +) + spacing * CGFloat(max(grid.rowHeights.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let grid = grid(width: bounds.width, subviews: subviews)
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
            Section("Wrapping") {
                ReadingColumns {
                    ReadingColumn("Current", previewGrade)
                    ReadingColumn("Steepest Climb", previewGrade)
                    ReadingColumn("Steepest Descent", MetricReading(value: "-8", unit: "%", spoken: "-8 percent"))
                }
            }
            Section("Accessory") {
                ReadingColumns {
                    ReadingColumn("Heart Rate", MetricReading(value: "156", unit: "bpm", spoken: "156 beats per minute"))
                    ReadingColumn("Zone", MetricReading(value: "3", spoken: "Zone 3, Aerobic")) {
                        Circle().fill(Color.hrZone(3)).frame(width: Spacing.sm, height: Spacing.sm)
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
