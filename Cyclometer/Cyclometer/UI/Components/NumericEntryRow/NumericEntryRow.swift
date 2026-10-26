import SwiftUI

/// A whole number typed on the number pad, in a `Form` row: the label, a trailing field with its unit,
/// and an error caption under them while the entry is out of range (#424, #429). S12's wheel
/// circumference and HR override rows (#439).
///
/// The number pad has no return key, so the row commits when focus leaves the field — via the
/// keyboard's Done button or a tap elsewhere. Validation stays with the caller: this only shows the
/// message it is given.
struct NumericEntryRow: View {
    private let label: LocalizedStringKey
    @Binding private var text: String
    private let placeholder: String
    private let unit: LocalizedStringKey
    /// `Text` rather than a string so each caller keeps its own copy's kind: a
    /// `LocalizedStringResource` wraps the English way on every device, a `String` by the
    /// device's language (#430).
    private let errorMessage: Text?
    private let onCommit: () -> Void

    @FocusState private var isFocused: Bool

    init(
        _ label: LocalizedStringKey,
        text: Binding<String>,
        placeholder: String,
        unit: LocalizedStringKey,
        errorMessage: Text? = nil,
        onCommit: @escaping () -> Void
    ) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.unit = unit
        self.errorMessage = errorMessage
        self.onCommit = onCommit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            LabeledContent(label) {
                HStack(spacing: Spacing.xs) {
                    TextField(placeholder, text: $text)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .focused($isFocused)
                    Text(unit).foregroundStyle(.secondary)
                }
            }
            if let errorMessage {
                errorMessage
                    .font(.caption)
                    .foregroundStyle(Color.cyRatingBad)
            }
        }
        .onChange(of: isFocused) { _, isFocused in
            if !isFocused { onCommit() }
        }
        .toolbar {
            // Only the focused row contributes, so the keyboard shows one Done however many rows
            // the form holds.
            if isFocused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isFocused = false }
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Placeholder") {
    Form {
        NumericEntryRow("Resting HR", text: .constant(""), placeholder: "60", unit: "bpm") {}
    }
}

#Preview("Valid") {
    Form {
        NumericEntryRow("Circumference", text: .constant("2140"), placeholder: "mm", unit: "mm") {}
    }
}

#Preview("Error") {
    Form {
        NumericEntryRow(
            "Circumference", text: .constant("900"), placeholder: "mm", unit: "mm",
            errorMessage: Text(WheelPreset.outOfRangeMessage)
        ) {}
    }
}

#Preview("Error, dark") {
    Form {
        NumericEntryRow(
            "Circumference", text: .constant("900"), placeholder: "mm", unit: "mm",
            errorMessage: Text(WheelPreset.outOfRangeMessage)
        ) {}
    }
    .preferredColorScheme(.dark)
}
