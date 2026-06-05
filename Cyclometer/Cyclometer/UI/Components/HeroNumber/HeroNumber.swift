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
    
    private var frameSize: CGFloat {
        switch size {
        case .small: 27
        case .medium: 50
        case .large:  100
        }
    }

    private var offset : CGFloat {
        switch size {
        case .small: -4
        case .medium: -6
        case .large:  -8
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            label.textCase(.uppercase)
            if alignment == .vertical {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(value).dDINCondensed(size: ptSize, relativeTo: .largeTitle).lineLimit(1).frame(height: frameSize).baselineOffset(offset).padding(0)
                    if !unit.isEmpty { Text(unit).textCase(.lowercase).font(.footnote).padding(0) }
                }
            } else {
                HStack(alignment: .lastTextBaseline, spacing: Spacing.xs) {
                    Text(value).dDINCondensed(size: ptSize, relativeTo: .largeTitle).lineLimit(1).frame(height: frameSize).baselineOffset(offset).padding(0)
                    if !unit.isEmpty { Text(unit).textCase(.lowercase).font(.footnote).baselineOffset(offset) }
                }.padding(0)
            }
        }
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

#Preview("Mixed") {
    VStack(alignment: .leading, spacing: Spacing.sm) {
        HeroNumber(34.1, unit: "max") {
            Text("MAX").font(.caption)
        }
        HeroNumber(34.1, unit: "max") {
            Text("mph").font(.caption)
        }
        .heroNumberSize(.small)
        .layout(.vertical)
    }
}
