import SwiftUI

/// Tap anywhere on a widget to open its detail sheet (UX.md §S05: "Tapping any widget opens a
/// detail sheet"). The one place a widget's tap is handled, so S07 edit mode (#141) adds its gate
/// here rather than in every widget.
///
/// It is also the widget's VoiceOver element (#361): one button reading `label` and `value`, whose
/// double-tap opens the same sheet. The modifier groups the children itself, so the button trait
/// never lands on each of a widget's texts, and taking the words as parameters means no widget can
/// adopt the tap without saying what VoiceOver reads.
///
/// The detail closure runs only when the sheet presents. That only keeps data off the dashboard's
/// hot path if the widget also takes it lazily, as `CadenceWidget`'s `detail:` does.
/// Detents belong to the detail content, not to this modifier.
private struct WidgetDetailModifier<Detail: View>: ViewModifier {
    let label: String
    let value: String
    @ViewBuilder let detail: () -> Detail
    @State private var isPresented = false

    @Environment(\.isEditingDashboard) private var isEditingDashboard

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            // S07: in edit mode a tap belongs to the edit controls, never the detail sheet.
            .onTapGesture { present() }
            .sheet(isPresented: $isPresented, content: detail)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(value)
            .accessibilityAction { present() }
            // Not a button while editing: the tap does nothing then. Removed rather than just not
            // added, because SwiftUI infers the trait from the tap gesture and the action.
            .accessibilityAddTraits(isEditingDashboard ? [] : .isButton)
            .accessibilityRemoveTraits(isEditingDashboard ? .isButton : [])
    }

    private func present() {
        if !isEditingDashboard { isPresented = true }
    }
}

extension EnvironmentValues {
    /// Whether the dashboard is in S07 edit mode (#141). Set by `RideDashboardView`.
    @Entry var isEditingDashboard = false
}

extension View {
    /// Opens `detail` on a tap, and makes the widget one VoiceOver button reading `label` (its title)
    /// and `value` (what the card currently shows, in words).
    func widgetDetail<Detail: View>(
        label: String,
        value: String = "",
        @ViewBuilder _ detail: @escaping () -> Detail
    ) -> some View {
        modifier(WidgetDetailModifier(label: label, value: value, detail: detail))
    }
}
