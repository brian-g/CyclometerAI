import SwiftUI

/// The scale S07 edit mode shrinks a widget to (#141: "scale down by 5 or 10%"), leaving the gap
/// that separates neighbouring cards. Shared by the card and its remove button, which sits on the
/// card's corner.
private let editingScale: CGFloat = 0.9

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
    @Environment(\.isEditingDashboard) private var isEditing

    func body(content: Content) -> some View {
        let card = RoundedRectangle(cornerRadius: isEditing ? Spacing.cornerMd : 0)
        content
            .clipShape(card)
            .overlay {
                if isEditing {
                    card.strokeBorder(Color.cyBorderStrong, lineWidth: Spacing.strokeHairline)
                }
            }
            .scaleEffect(isEditing ? editingScale : 1)
            .animation(.default, value: isEditing)
    }
}

/// S07 edit mode's remove button (#141), centred on the card's top-leading corner, where the scale
/// left it. Applied outside the wiggle, so it holds still while the card moves under it.
private struct DashboardRemoveButton: ViewModifier {
    let title: String
    let onRemove: () -> Void

    @Environment(\.isEditingDashboard) private var isEditing

    func body(content: Content) -> some View {
        content.overlay {
            if isEditing {
                GeometryReader { proxy in
                    button.position(
                        x: proxy.size.width * (1 - editingScale) / 2,
                        y: proxy.size.height * (1 - editingScale) / 2
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

/// The SpringBoard wiggle while S07 edit mode is on (#141). None under Reduce Motion.
private struct DashboardWiggle: ViewModifier {
    /// Offsets this widget's swing, in cycles, so neighbours don't wiggle in step.
    let phase: Double

    @Environment(\.isEditingDashboard) private var isEditing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far a widget's corners swing either way, whatever its size. A fixed angle swung a
    /// full-width widget's corners three times as far as a 1×1's, into the cells around it.
    private static let cornerTravel: CGFloat = 1.5
    /// One full swing and back, in seconds.
    private static let period = 0.26

    private var isWiggling: Bool { isEditing && !reduceMotion }

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
    /// S07 edit mode's card (#141), shown while `EnvironmentValues.isEditingDashboard` is set.
    func dashboardEditCard() -> some View {
        modifier(DashboardEditCard())
    }

    /// S07 edit mode's wiggle (#141), `phase` cycles out of step with its neighbours.
    func dashboardWiggle(phase: Double) -> some View {
        modifier(DashboardWiggle(phase: phase))
    }

    /// S07 edit mode's remove button for the widget `title` (#141). Apply it outside
    /// `dashboardWiggle`, so the button stays still.
    func dashboardRemoveButton(title: String, onRemove: @escaping () -> Void) -> some View {
        modifier(DashboardRemoveButton(title: title, onRemove: onRemove))
    }
}
