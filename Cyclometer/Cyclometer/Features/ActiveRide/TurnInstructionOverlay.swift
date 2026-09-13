import SwiftUI

/// The turn the rider is about to make, centred over the dashboard (#197 review, Sketch
/// "Sxx - Route overlay"): the arrow large, the instruction under it, on a card the dashboard
/// stays visible through.
///
/// Solid rather than a material — a blur would smear exactly the numbers the rider is watching.
/// Purely presentational: `NavigationFeature` sets the maneuver and takes it down after
/// `instructionDuration`.
struct TurnInstructionOverlay: View {
    let maneuver: Maneuver

    var body: some View {
        let text = NavigationFeature.instructionText(for: maneuver)
        VStack(spacing: 0) {
            Image(systemName: maneuver.direction.systemImage)
                .font(.cyTurnGlyph)
                .foregroundStyle(Color.cyPrimaryDark)
            Text(text)
                .font(.cyTurnInstruction)
                .foregroundStyle(Color.cyTextPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .padding(Spacing.sm)
        // The design's square is the smallest the card gets; a cue's own words can run longer.
        .frame(minWidth: Spacing.turnOverlay, minHeight: Spacing.turnOverlay)
        .background {
            let card = RoundedRectangle(cornerRadius: Spacing.cornerLg, style: .continuous)
            // The design's fill is `borderSubtle`'s value exactly; no background token matches it.
            card.fill(Color.cyBorderSubtle)
                .overlay(card.strokeBorder(Color.cyBorderStrong, lineWidth: Spacing.strokeHairline))
                .opacity(Opacity.turnOverlay)
        }
        .padding(.horizontal, Spacing.lg)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

extension Maneuver.Direction {
    /// The turn's arrow, in SF Symbols' own navigation vocabulary.
    var systemImage: String {
        switch self {
        case .left: "arrow.turn.up.left"
        case .right: "arrow.turn.up.right"
        case .slightLeft: "arrow.up.left"
        case .slightRight: "arrow.up.right"
        // A maneuver does not say which way to turn around, so neither does its arrow.
        case .uTurn: "arrow.uturn.down"
        }
    }
}

// MARK: - Previews

private func previewManeuver(_ direction: Maneuver.Direction, name: String? = nil) -> Maneuver {
    Maneuver(
        coordinate: RouteCoordinate(latitude: 0, longitude: 0, elevationMeters: nil),
        direction: direction,
        name: name,
        distanceAlongRouteMeters: 0
    )
}

#Preview("Turn left") {
    TurnInstructionOverlay(maneuver: previewManeuver(.left))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cyBgSecondary)
}

#Preview("Cue's own words") {
    TurnInstructionOverlay(maneuver: previewManeuver(.right, name: "Turn right onto County Road S"))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cyBgSecondary)
}
