import SwiftUI

enum HeroUnitAlignment: Hashable { case vertical, horizontal }
enum HeroSize: Hashable { case small, medium, large }

struct HeroNumber<Label: View>: View {
    let value: String
    let unit: String
    var size: HeroSize = .large
    var alignment: HeroUnitAlignment = .horizontal
    var color: Color = .primary
    var accessory: AnyView? = nil
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

    // MARK: - Binding inits

    init(_ value: Binding<String>, unit: String) where Label == EmptyView {
        self.value = value.wrappedValue
        self.unit = unit
        self.label = EmptyView()
    }

    init(_ value: Binding<Double>, decimals: Int = 1, unit: String) where Label == EmptyView {
        self.value = value.wrappedValue.formatted(.number.precision(.fractionLength(decimals)))
        self.unit = unit
        self.label = EmptyView()
    }

    init(_ value: Binding<String>, unit: String, @ViewBuilder label: () -> Label) {
        self.value = value.wrappedValue
        self.unit = unit
        self.label = label()
    }

    init(_ value: Binding<Double>, decimals: Int = 1, unit: String, @ViewBuilder label: () -> Label) {
        self.value = value.wrappedValue.formatted(.number.precision(.fractionLength(decimals)))
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

    /// Optional view shown immediately before the value, baseline-aligned with
    /// it (e.g. a trend chevron). Lives inside HeroNumber so callers don't have
    /// to re-derive the value's baseline.
    func heroAccessory<A: View>(@ViewBuilder _ make: () -> A) -> Self {
        var copy = self
        copy.accessory = AnyView(make())
        return copy
    }

    // MARK: - Layout constants

    private var ptSize: CGFloat {
        switch size {
        case .small:  34
        case .medium: 68
        case .large:  136
        }
    }

    /// Layout height offered to the parent. Smaller than `ptSize` so the text
    /// overflows the frame visually while the widget grid takes a compact slot.
    private var frameSize: CGFloat {
        switch size {
        case .small:  27
        case .medium: 50
        case .large:  100
        }
    }

    private var offset: CGFloat {
        switch size {
        case .small:  -4
        case .medium: -6
        case .large:  -8
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            label.textCase(.uppercase)
            if alignment == .vertical {
                VStack(alignment: .trailing, spacing: 0) {
                    HStack(alignment: .lastTextBaseline, spacing: Spacing.xs) {
                        if let accessory { accessory }
                        scaledValue
                    }
                    if !unit.isEmpty { unitLabel }
                }
            } else {
                HStack(alignment: .lastTextBaseline, spacing: Spacing.xs) {
                    if let accessory { accessory }
                    scaledValue
                    if !unit.isEmpty { unitLabel.baselineOffset(offset) }
                }
            }
        }
    }

    // MARK: - Private helpers

    private var scaledValue: some View {
        Text(value)
            .dDINCondensed(size: ptSize, relativeTo: .largeTitle)
            .lineLimit(1)
            .foregroundStyle(color)
            .frame(height: frameSize)
            .baselineOffset(offset)
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
