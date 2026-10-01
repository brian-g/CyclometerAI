import SwiftUI

/// Tap anywhere on a widget to open its detail sheet (UX.md §S05: "Tapping any widget opens a
/// detail sheet"). The one place a widget's tap is handled, so S07 edit mode (#141) can turn it
/// off here rather than in every widget.
///
/// The detail closure runs only when the sheet presents, so a widget can hand over large,
/// fast-changing data (cadence samples, the track) without the dashboard reading it every tick.
/// Detents belong to the detail content, not to this modifier.
private struct WidgetDetailModifier<Detail: View>: ViewModifier {
    @ViewBuilder let detail: () -> Detail
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture { isPresented = true }
            .sheet(isPresented: $isPresented, content: detail)
    }
}

extension View {
    func widgetDetail<Detail: View>(@ViewBuilder _ detail: @escaping () -> Detail) -> some View {
        modifier(WidgetDetailModifier(detail: detail))
    }
}
