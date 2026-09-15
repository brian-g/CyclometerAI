import SwiftUI

// MARK: - W9 Directions Widget

/// W9 — Directions (#200): the next turn's arrow and how far along the route it is, read from
/// `NavigationFeature`'s `nextManeuver` and `distanceToNextTurnMeters`. Tapping opens the map sheet,
/// the same one W8 opens (UX.md §S05 W9, "Sheet: Map").
///
/// Always on the dashboard: on a free ride it reads "No Route". Hiding it is the rider's call once
/// S07/S08 customisation exists, not the dashboard's.
struct DirectionsWidget: View {
    let hasRoute: Bool
    /// The turn ahead. Shown only together with a distance: without one — before the first match,
    /// off route, past the last turn — there is nothing honest to point at, and the widget reads "—".
    let nextTurn: Maneuver?
    let distanceMeters: Double?
    let unit: UnitSystem
    var size: WidgetSize = .oneByOne   // only .oneByOne / .twoByOne used by W9
    /// The map sheet's inputs, as `MapWidget` takes them.
    var coordinates: [Coordinate] = []
    var route: [RouteCoordinate] = []
    var sheetOrientation: MapOrientation = .headingUp
    var onOrientationToggle: () -> Void = {}

    @State private var showMapSheet = false

    var body: some View {
        content
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.cyBgSecondary)
            .contentShape(Rectangle())
            .onTapGesture { showMapSheet = true }
            .liveMapSheet(
                isPresented: $showMapSheet,
                coordinates: coordinates,
                route: route,
                orientation: sheetOrientation,
                onOrientationToggle: onOrientationToggle
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(.isButton)
    }

    // MARK: - Layout Variants

    @ViewBuilder
    private var content: some View {
        switch size {
        case .oneByOne, .twoByTwo:
            VStack(alignment: .leading, spacing: 0) {
                WidgetLabel("Directions")
                hero
                Spacer()
            }
        case .twoByOne:
            VStack(alignment: .leading, spacing: 0) {
                WidgetLabel("Directions")
                HStack(alignment: .lastTextBaseline, spacing: Spacing.lg) {
                    hero
                    Spacer()
                    instruction
                        .multilineTextAlignment(.trailing)
                }
                Spacer()
            }
        }
    }

    // MARK: - Sub-Views

    @ViewBuilder
    private var hero: some View {
        if let turn {
            HeroNumber(turn.distance.value, unit: turn.distance.unit)
                .heroNumberSize(.medium)
                .heroAccessory {
                    Image(systemName: turn.maneuver.direction.systemImage)
                        .font(.cyTurnGlyphCompact)
                        .foregroundStyle(Color.cyPrimaryDark)
                }
        } else if hasRoute {
            HeroNumber("—", unit: "").heroNumberSize(.medium)
        } else {
            Text("No Route")
                .font(.cyCaption)
                .foregroundStyle(.cyTextTertiary)
        }
    }

    /// The cue's own words, or the direction — the text the centred overlay shows for the same turn.
    @ViewBuilder
    private var instruction: some View {
        if let turn {
            Text(NavigationFeature.instructionText(for: turn.maneuver))
                .font(.subheadline)
                .foregroundStyle(Color.cyTextSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: - Computed Display Values

    private var turn: (maneuver: Maneuver, distance: (value: String, unit: String))? {
        guard let nextTurn, let distanceMeters else { return nil }
        return (nextTurn, unit.turnDistance(fromMeters: distanceMeters))
    }

    private var accessibilityText: String {
        if let turn {
            return "\(NavigationFeature.instructionText(for: turn.maneuver)) in \(turn.distance.value) \(turn.distance.unit)"
        }
        return hasRoute ? "Directions, no turn ahead" : "No route"
    }
}

// MARK: - Previews

private let previewTurn = Maneuver(
    coordinate: RouteCoordinate(latitude: 0, longitude: 0, elevationMeters: nil),
    direction: .right,
    name: "Turn right onto County Road S",
    distanceAlongRouteMeters: 0
)

#Preview("2×1 — Turn") {
    DirectionsWidget(hasRoute: true, nextTurn: previewTurn, distanceMeters: 347, unit: .metric, size: .twoByOne)
        .frame(width: 393, height: 96)
}

#Preview("1×1 — Turn") {
    DirectionsWidget(hasRoute: true, nextTurn: previewTurn, distanceMeters: 347, unit: .metric)
        .frame(width: 196, height: 96)
}

#Preview("1×1 — No Turn Ahead") {
    DirectionsWidget(hasRoute: true, nextTurn: nil, distanceMeters: nil, unit: .metric)
        .frame(width: 196, height: 96)
}

#Preview("1×1 — No Route") {
    DirectionsWidget(hasRoute: false, nextTurn: nil, distanceMeters: nil, unit: .metric)
        .frame(width: 196, height: 96)
}
