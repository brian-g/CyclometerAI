import SwiftUI

enum HeroUnitAlignment: Hashable { case vertical, horizontal }
enum HeroSize: Hashable { case small, medium, large }

struct HeroNumber<Label: View>: View {
    let value: String
    let unit: String
    var size: HeroSize = .large
    var alignment: HeroUnitAlignment = .horizontal
    var color: Color = .primary
    let label: Label

    // MARK: - Plain-value inits

    init(_ value: String, unit: String) where Label == EmptyView {
        self.value = value
        self.unit = unit
        self.label = EmptyView()
    }

    init(_ value: Double, decimals: Int = 1, unit: String) where Label == EmptyView {
        self.value = value.formatted(.number.precision(.fractionLength(decimals)))
        self.unit = unit
        self.label = EmptyView()
    }

    init(_ value: String, unit: String, @ViewBuilder label: () -> Label) {
        self.value = value
        self.unit = unit
        self.label = label()
    }

    init(_ value: Double, decimals: Int = 1, unit: String, @ViewBuilder label: () -> Label) {
        self.value = value.formatted(.number.precision(.fractionLength(decimals)))
        self.unit = unit
        self.label = label()
    }

    // MARK: - Modifiers

    func heroNumberSize(_ size: HeroSize) -> Self {
        var copy = self
        copy.size = size
        return copy
    }

    func layout(_ alignment: HeroUnitAlignment) -> Self {
        var copy = self
        copy.alignment = alignment
        return copy
    }

    func valueColor(_ color: Color) -> Self {
        var copy = self
        copy.color = color
        return copy
    }

    // MARK: - Layout constants

    /// Nominal font size for each size class. Also the maximum: the value never
    /// renders larger, but `minimumScaleFactor` lets it shrink continuously if a
    /// container ever constrains it smaller than the text needs.
    private var ptSize: CGFloat {
        switch size {
        case .small:  34
        case .medium: 68
        case .large:  136
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            label.textCase(.uppercase)
            if alignment == .vertical {
                VStack(alignment: .trailing, spacing: 0) {
                    scaledValue
                    if !unit.isEmpty { unitLabel }
                }
            } else {
                HStack(alignment: .lastTextBaseline, spacing: Spacing.xs) {
                    scaledValue
                    if !unit.isEmpty { unitLabel }
                }
            }
        }
    }

    // MARK: - Private helpers

    private var scaledValue: some View {
        Text(value)
            .dDINCondensed(size: ptSize, relativeTo: .largeTitle)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(color)
    }

    private var unitLabel: some View {
        Text(unit).textCase(.lowercase).font(.footnote)
    }
}

// MARK: - Previews

#Preview("Sizes") {
    VStack(alignment: .leading, spacing: Spacing.lg) {
        HeroNumber(28.4, unit: "mph")
        HeroNumber(28.4, unit: "mph").heroNumberSize(.medium)
        HeroNumber(28.4, unit: "mph").heroNumberSize(.small)
    }
    .padding()
}

#Preview("With Labels") {
    VStack(alignment: .leading, spacing: Spacing.lg) {
        HeroNumber(12.3, unit: "mi") {
            Text("Distance").font(.caption)
        }
        .heroNumberSize(.small)

        HeroNumber("155", unit: "bpm") {
            Text("Heart Rate").font(.caption)
        }
        .heroNumberSize(.medium)

        HeroNumber(28.4, unit: "mph") {
            Text("Speed").font(.caption)
        }
    }
    .padding()
}

#Preview("Vertical Layout") {
    VStack(alignment: .leading, spacing: Spacing.lg) {
        HeroNumber(26.7, unit: "avg") {
            Text("Average").font(.caption)
        }
        .heroNumberSize(.small)
        .layout(.vertical)

        HeroNumber(34.1, unit: "mph") {
            Text("Maximum").font(.caption)
        }
        .heroNumberSize(.small)
        .layout(.vertical)

        HeroNumber(34.1, unit: "max") {
            Text("MAX").font(.caption)
        }
        .heroNumberSize(.medium)
        .layout(.vertical)

        HeroNumber(34.1, unit: "max") {
            Text("MAX").font(.caption)
        }
        .heroNumberSize(.large)
        .layout(.vertical)
    }
    .padding()
}

#Preview("Color + Empty State") {
    VStack(alignment: .leading, spacing: Spacing.sm) {
        HeroNumber(34.1, unit: "mph")
            .valueColor(.accentColor)
        HeroNumber("—", unit: "mph")
            .heroNumberSize(.medium)
        HeroNumber("—", unit: "bpm")
            .heroNumberSize(.small)
            .valueColor(.secondary)
    }
    .padding()
}
