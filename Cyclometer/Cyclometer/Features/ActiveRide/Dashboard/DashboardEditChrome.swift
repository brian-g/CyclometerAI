import SwiftUI

extension WidgetSize {
    /// The scale S07 edit mode shrinks a widget of this size to, leaving the gap that separates
    /// neighbouring cards (#141 review): 90% for one column, 95% for two, so a full-width card's
    /// sides inset as far as a 1×1's. Shared by the card and its remove button, which sits on the
    /// card's corner.
    fileprivate var editingScale: CGFloat { columns == 1 ? 0.9 : 0.95 }
}

/// S07 edit mode's card for one dashboard widget (#141): the widget shrinks into a rounded card with
/// a hairline border. Outside edit mode it adds nothing.
///
/// A card, not glass: Liquid Glass casts a rim and shadow past its shape, so glass frames tiled
/// edge to edge bled into each other and into the cell a removed widget left empty (#141 review).
///
/// The card, `DashboardWiggle` and `DashboardRemoveButton` are separate modifiers so the card can
/// wiggle under a remove button that holds still, and so the still parts can be snapshotted. All
/// three are modifiers rather than an `if` around the widget, so entering edit mode keeps each
/// widget's identity — the live map isn't rebuilt.
private struct DashboardEditCard: ViewModifier {
    let size: WidgetSize

    @Environment(\.isEditingDashboard) private var isEditing

    func body(content: Content) -> some View {
        let card = RoundedRectangle(cornerRadius: Spacing.cornerMd)
        content
            // Clips to the card only while editing. Otherwise the mask ignores the safe area, as
            // W8 does, so a map in the top or bottom rows still bleeds under the Dynamic Island or
            // the home indicator (UX.md §S05) — a plain clip cut it at the safe-area edge.
            .mask {
                if isEditing {
                    card
                } else {
                    Rectangle().ignoresSafeArea()
                }
            }
            .overlay {
                if isEditing {
                    card.strokeBorder(Color.cyBorderStrong, lineWidth: Spacing.strokeHairline)
                }
            }
            .scaleEffect(isEditing ? size.editingScale : 1)
    }
}

/// S07 edit mode's remove button (#141), centred on the card's top-leading corner, where the scale
/// left it. Applied outside the wiggle, so it holds still while the card moves under it.
private struct DashboardRemoveButton: ViewModifier {
    let title: String
    let size: WidgetSize
    let onRemove: () -> Void

    @Environment(\.isEditingDashboard) private var isEditing

    func body(content: Content) -> some View {
        content.overlay {
            if isEditing {
                GeometryReader { proxy in
                    button.position(
                        x: proxy.size.width * (1 - size.editingScale) / 2,
                        y: proxy.size.height * (1 - size.editingScale) / 2
                    )
                }
            }
        }
    }

    /// A full tap target around the glyph, which overhangs the card into the cells above and to the
    /// left; `DashboardPageView` draws widgets in reading order so it lands on top of them.
    private var button: some View {
        Button(action: onRemove) {
            Image(systemName: "minus.circle.fill")
                .font(.title2.weight(.semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.cyTextInverted, Color.cyDestructive)
                .frame(width: Spacing.mapControl, height: Spacing.mapControl)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(title)")
    }
}

/// S07 edit mode's slot for an empty cell (#368): a dashed outline where a 1×1 card would sit, which
/// opens S08 aimed at that cell. Outside edit mode it draws nothing and takes no taps (UX.md §S05
/// "Empty cells"). It doesn't wiggle: there's no widget to move.
struct DashboardEmptySlot: View {
    let cell: DashboardGrid.Cell
    let onTap: () -> Void

    @Environment(\.isEditingDashboard) private var isEditing

    var body: some View {
        if isEditing {
            Button(action: onTap) {
                RoundedRectangle(cornerRadius: Spacing.cornerMd)
                    .strokeBorder(
                        Color.cyBorderStrong,
                        style: StrokeStyle(lineWidth: Spacing.strokeHairline, dash: [Spacing.strokeDash])
                    )
                    .scaleEffect(WidgetSize.oneByOne.editingScale)
                    // The whole cell, not just the outline.
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Empty, \(cell.spokenPosition(for: .oneByOne))")
            .accessibilityHint("Add widget here")
        }
    }
}

/// S07 edit mode's VoiceOver element for a widget (#367): the card read as one element, "Speed,
/// row 1, full width", with a Move action for each way it can go. Moving needs a drag otherwise.
/// An overlay rather than an `if` around the widget, which would rebuild it — the live map — on
/// entering edit mode; the widget's own elements are hidden while editing.
private struct DashboardMoveActions: ViewModifier {
    let title: String
    let placement: WidgetPlacement
    let targets: [(direction: DashboardGrid.Direction, cell: DashboardGrid.Cell)]
    let onMove: (DashboardGrid.Cell) -> Void

    @Environment(\.isEditingDashboard) private var isEditing

    func body(content: Content) -> some View {
        content
            .accessibilityHidden(isEditing)
            .overlay {
                if isEditing {
                    Color.clear
                        .allowsHitTesting(false)
                        .accessibilityElement()
                        .accessibilityLabel("\(title), \(placement.cell.spokenPosition(for: placement.size))")
                        .accessibilityActions {
                            ForEach(targets, id: \.direction) { target in
                                Button(target.direction.title) { onMove(target.cell) }
                            }
                        }
                }
            }
    }
}

extension DashboardGrid.Cell {
    /// Where VoiceOver says a `size` widget or empty slot with its top-left here sits: "row 3,
    /// left" (#368), or "full width" for a widget spanning both columns (#367).
    func spokenPosition(for size: WidgetSize) -> String {
        let side = size.columns == DashboardGrid.columns ? "full width" : column == 0 ? "left" : "right"
        return "row \(row + 1), \(side)"
    }
}

/// The SpringBoard wiggle while S07 edit mode is on (#141). None under Reduce Motion, nor while the
/// widget is held by a drag (#367), as on SpringBoard.
private struct DashboardWiggle: ViewModifier {
    /// Offsets this widget's swing, in cycles, so neighbours don't wiggle in step.
    let phase: Double
    let isHeld: Bool

    @Environment(\.isEditingDashboard) private var isEditing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far a widget's corners swing either way, whatever its size. A fixed angle swung a
    /// full-width widget's corners three times as far as a 1×1's, into the cells around it.
    private static let cornerTravel: CGFloat = 1.5
    /// One full swing and back, in seconds.
    private static let period = 0.26

    private var isWiggling: Bool { isEditing && !reduceMotion && !isHeld }

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: !isWiggling)) { timeline in
            let date = timeline.date, phase = phase, isWiggling = isWiggling
            content.visualEffect { content, proxy in
                content.rotationEffect(Self.angle(at: date, phase: phase, size: proxy.size, isWiggling: isWiggling))
            }
        }
    }

    /// The swing at `date` that moves a `size` widget's corners `cornerTravel` at its peak.
    nonisolated private static func angle(at date: Date, phase: Double, size: CGSize, isWiggling: Bool) -> Angle {
        let halfDiagonal = hypot(size.width, size.height) / 2
        guard isWiggling, halfDiagonal > cornerTravel else { return .zero }
        let cycle = date.timeIntervalSinceReferenceDate / period
        return .radians(sin((cycle + phase) * 2 * .pi) * asin(cornerTravel / halfDiagonal))
    }
}

extension View {
    /// S07 edit mode's card for a widget placed at `size` (#141), shown while
    /// `EnvironmentValues.isEditingDashboard` is set.
    func dashboardEditCard(size: WidgetSize) -> some View {
        modifier(DashboardEditCard(size: size))
    }

    /// S07 edit mode's wiggle (#141), `phase` cycles out of step with its neighbours. Still while
    /// `isHeld` by a drag (#367).
    func dashboardWiggle(phase: Double, isHeld: Bool) -> some View {
        modifier(DashboardWiggle(phase: phase, isHeld: isHeld))
    }

    /// S07 edit mode's VoiceOver element for the widget `title` at `placement` (#367), with a Move
    /// action to each of `targets`.
    func dashboardMoveActions(
        title: String,
        placement: WidgetPlacement,
        targets: [(direction: DashboardGrid.Direction, cell: DashboardGrid.Cell)],
        onMove: @escaping (DashboardGrid.Cell) -> Void
    ) -> some View {
        modifier(DashboardMoveActions(title: title, placement: placement, targets: targets, onMove: onMove))
    }

    /// S07 edit mode's remove button for the widget `title` (#141). Apply it outside
    /// `dashboardWiggle`, so the button stays still.
    func dashboardRemoveButton(title: String, size: WidgetSize, onRemove: @escaping () -> Void) -> some View {
        modifier(DashboardRemoveButton(title: title, size: size, onRemove: onRemove))
    }
}
