import SwiftUI

extension View {
    /// A 1×1 widget's SF Symbol in its lower right (#491, W21's first). It marks the card at a
    /// glance, whatever the card reads, so it is drawn in every state. Applied inside the card,
    /// before its background and `.widgetDetail`, which keeps VoiceOver from reading it. A widget
    /// that has other sizes passes nil for them, which draws nothing.
    func widgetSymbol(_ systemName: String?) -> some View {
        overlay(alignment: .bottomTrailing) {
            if let systemName {
                Image(systemName: systemName)
                    .font(.title2)
                    .foregroundStyle(Color.cyTextSecondary)
                    .padding(Spacing.sm)
            }
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 0) {
        WidgetLabel("Duration")
        HeroNumber("26:00", unit: "").heroNumberSize(.medium)
        Spacer()
    }
    .padding(Spacing.sm)
    .frame(width: 196, height: 96, alignment: .leading)
    .widgetSymbol("stopwatch")
    .background(Color.cyBgSecondary)
}
