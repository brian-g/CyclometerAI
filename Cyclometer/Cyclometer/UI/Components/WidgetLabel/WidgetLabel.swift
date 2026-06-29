import SwiftUI

/// Uppercase secondary caption shown as the title above a dashboard widget's
/// value (e.g. "SPEED", "CADENCE", "HEART RATE"). Centralises the label styling
/// so each widget doesn't re-declare the font / case / colour.
struct WidgetLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Spacing.sm) {
        WidgetLabel("Speed")
        WidgetLabel("Cadence")
        WidgetLabel("Heart Rate")
    }
    .padding()
}
