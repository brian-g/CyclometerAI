import SwiftUI

/// The close every sheet but the dashboard carries in its upper-left corner (UX.md §Sheet standards,
/// #335): the system `Button(role: .close)` at `.cancellationAction`, so it sits in the sheet's corner
/// and moves with the detent. The one place that rule lives, so a new sheet can't drift from it.
///
/// Apply it inside the sheet's `NavigationStack`, where a toolbar goes; it adds its own `.toolbar`, so a
/// sheet's other items compose with it. With no `action` it calls `dismiss`, which at the stack's root
/// closes the sheet.
private struct SheetCloseButton: ViewModifier {
    let isDisabled: Bool
    let action: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .close) {
                    if let action { action() } else { dismiss() }
                }
                .disabled(isDisabled)
            }
        }
    }
}

extension View {
    /// The sheet's upper-left close. `action` replaces the plain dismiss, for a sheet whose store owns
    /// its presentation.
    func sheetCloseButton(disabled: Bool = false, action: (() -> Void)? = nil) -> some View {
        modifier(SheetCloseButton(isDisabled: disabled, action: action))
    }
}

// MARK: - Previews

#Preview("Sheet") {
    Color.cyBgSecondary
        .sheet(isPresented: .constant(true)) {
            NavigationStack {
                List { Text("Content") }
                    .navigationTitle("Sheet")
                    .navigationBarTitleDisplayMode(.inline)
                    .sheetCloseButton()
            }
            .presentationDetents([.medium, .large])
        }
}

#Preview("Disabled") {
    Color.cyBgSecondary
        .sheet(isPresented: .constant(true)) {
            NavigationStack {
                List { Text("Content") }
                    .navigationTitle("Sheet")
                    .navigationBarTitleDisplayMode(.inline)
                    .sheetCloseButton(disabled: true) {}
            }
            .presentationDetents([.medium, .large])
        }
}
