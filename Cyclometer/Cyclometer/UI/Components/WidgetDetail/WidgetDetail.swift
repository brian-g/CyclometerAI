import SwiftUI

/// Tap anywhere on a widget to open its detail sheet (UX.md §S05: "Tapping any widget opens a
/// detail sheet"). The one place a widget's tap is handled, so S07 edit mode (#141) adds its gate
/// here rather than in every widget.
///
/// The detail closure runs only when the sheet presents. That only keeps data off the dashboard's
/// hot path if the widget also takes it lazily, as `CadenceWidget`'s `detail:` does.
/// Detents belong to the detail content, not to this modifier.
private struct WidgetDetailModifier<Detail: View>: ViewModifier {
    @ViewBuilder let detail: () -> Detail
    @State private var isPresented = false

    @Environment(\.isEditingDashboard) private var isEditingDashboard

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            // S07: in edit mode a tap belongs to the edit controls, never the detail sheet.
            .onTapGesture { if !isEditingDashboard { isPresented = true } }
            .sheet(isPresented: $isPresented, content: detail)
    }
}

extension EnvironmentValues {
    /// Whether the dashboard is in S07 edit mode (#141). Set by `RideDashboardView`.
    @Entry var isEditingDashboard = false
}

extension View {
    func widgetDetail<Detail: View>(@ViewBuilder _ detail: @escaping () -> Detail) -> some View {
        modifier(WidgetDetailModifier(detail: detail))
    }
}
