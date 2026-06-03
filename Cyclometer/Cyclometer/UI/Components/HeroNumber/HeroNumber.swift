import SwiftUI

enum HeroUnitAlignment: Hashable { case vertical, horizontal }
enum HeroSize: Hashable { case small, medium, large }

struct HeroNumber<Label: View>: View {
    let value: String
    let unit: String
    var size: HeroSize = .large
    var alignment: HeroUnitAlignment = .horizontal
    let label: Label

    init(_ value: String, unit: String) where Label == EmptyView {
        self.value = value; self.unit = unit; self.label = EmptyView()
    }

    init(_ value: Double, decimals: Int = 1, unit: String) where Label == EmptyView {
        self.value = value.formatted(.number.precision(.fractionLength(decimals)))
        self.unit = unit
        self.label = EmptyView()
    }

    init(_ value: String, unit: String, @ViewBuilder label: () -> Label) {
        self.value = value; self.unit = unit; self.label = label()
    }

    init(_ value: Double, decimals: Int = 1, unit: String, @ViewBuilder label: () -> Label) {
        self.value = value.formatted(.number.precision(.fractionLength(decimals)))
        self.unit = unit
        self.label = label()
    }

    func heroNumberSize(_ size: HeroSize) -> Self {
        var copy = self; copy.size = size; return copy
    }

    func layout(_ alignment: HeroUnitAlignment) -> Self {
        var copy = self; copy.alignment = alignment; return copy
    }

    private var ptSize: CGFloat {
        switch size {
        case .small:  34
        case .medium: 68
        case .large:  136
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            label
            if alignment == .vertical {
                VStack(alignment: .trailing, spacing: Spacing.xs) {
                    Text(value).dDINCondensed(size: ptSize, relativeTo: .largeTitle)
                    Text(unit).font(.footnote)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Text(value).dDINCondensed(size: ptSize, relativeTo: .largeTitle)
                    if !unit.isEmpty { Text(unit).font(.footnote) }
                }
            }
        }
    }
}
