import SwiftUI

/// S07 edit mode's look for one dashboard widget (#141), modelled on SpringBoard: the widget shrinks
/// inside a glass frame that fills its cells, with a remove button at its top-leading corner.
/// Outside edit mode it adds nothing. The wiggle is `DashboardWiggle`, kept apart so this stays
/// still enough to snapshot.
///
/// Modifiers rather than an `if` around the widget, so entering edit mode keeps each widget's
/// identity — the live map isn't rebuilt.
private struct DashboardEditFrame: ViewModifier {
    let title: String
    let onRemove: () -> Void

    @Environment(\.isEditingDashboard) private var isEditing

    /// Room around the widget for its glass frame (#141: "scale down by 5 or 10%").
    private static let editingScale: CGFloat = 0.9
    /// The frame's gap to the cell edge, so neighbouring frames don't touch.
    private static let frameInset = Spacing.xs / 2

    func body(content: Content) -> some View {
        content
            .scaleEffect(isEditing ? Self.editingScale : 1)
            .background {
                if isEditing {
                    Color.clear
                        .glassEffect(.regular, in: .rect(cornerRadius: Spacing.cornerMd))
                        .padding(Self.frameInset)
                }
            }
            .overlay(alignment: .topLeading) {
                if isEditing { removeButton }
            }
            .animation(.default, value: isEditing)
    }

    /// The glyph sits on the frame's corner; the hit area around it is a full tap target.
    private var removeButton: some View {
        Button(action: onRemove) {
            Image(systemName: "minus.circle.fill")
                .font(.title3)
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.cyTextPrimary, Color.cyBgTertiary)
                .frame(width: Spacing.mapControl, height: Spacing.mapControl, alignment: .topLeading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(title)")
    }
}

/// The SpringBoard wiggle while S07 edit mode is on (#141). None under Reduce Motion.
private struct DashboardWiggle: ViewModifier {
    /// Offsets this widget's swing, in cycles, so neighbours don't wiggle in step.
    let phase: Double

    @Environment(\.isEditingDashboard) private var isEditing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Peak swing either way. Small, because a 2×2 widget is the screen's full width: at 1° its
    /// corners already travel about 3.5 pt.
    private static let degrees = 1.0
    /// One full swing and back, in seconds.
    private static let period = 0.26

    private var isWiggling: Bool { isEditing && !reduceMotion }

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: !isWiggling)) { timeline in
            content.rotationEffect(.degrees(angle(at: timeline.date)))
        }
    }

    private func angle(at date: Date) -> Double {
        guard isWiggling else { return 0 }
        let cycle = date.timeIntervalSinceReferenceDate / Self.period
        return sin((cycle + phase) * 2 * .pi) * Self.degrees
    }
}

extension View {
    /// S07 edit mode's frame and remove button for the widget `title` (#141), shown while
    /// `EnvironmentValues.isEditingDashboard` is set.
    func dashboardEditFrame(title: String, onRemove: @escaping () -> Void) -> some View {
        modifier(DashboardEditFrame(title: title, onRemove: onRemove))
    }

    /// S07 edit mode's wiggle (#141), `phase` cycles out of step with its neighbours.
    func dashboardWiggle(phase: Double) -> some View {
        modifier(DashboardWiggle(phase: phase))
    }
}
