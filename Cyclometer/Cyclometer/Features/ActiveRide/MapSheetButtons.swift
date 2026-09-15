import SwiftUI

/// Which way up the full-screen map sheet draws the map (#199). Shows the saved orientation. A tap
/// switches it, or, once the rider has panned away, brings the camera back to it
/// (`LiveMapCamera.orientationTap`).
struct MapOrientationButton: View {
    let orientation: MapOrientation
    let action: () -> Void

    var body: some View {
        MapSheetButton(
            title: "Map orientation",
            systemImage: orientation == .headingUp ? "location.north.line.fill" : "n.circle",
            action: action
        )
        .accessibilityValue(orientation == .headingUp ? "Heading up" : "North up")
    }
}

/// Frames the whole route, flat (#199). The camera stops following the rider until the orientation
/// button brings it back.
struct RouteOverviewButton: View {
    let action: () -> Void

    var body: some View {
        MapSheetButton(
            title: "Show whole route",
            systemImage: "point.topleft.down.to.point.bottomright.curvepath",
            action: action
        )
    }
}

/// Sized and shaped like MapKit's own map controls, so it sits in one column with them: a glass circle
/// of `Spacing.mapControl`, with no button-style padding to make it larger. The icon-only `Label` keeps
/// the title for VoiceOver, and the glyph takes an explicit token rather than the ambient accent.
private struct MapSheetButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.cyPrimary)
                .frame(width: Spacing.mapControl, height: Spacing.mapControl)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HStack {
        MapOrientationButton(orientation: .headingUp) {}
        MapOrientationButton(orientation: .northUp) {}
        RouteOverviewButton {}
    }
    .padding()
    .background(Color.cyBgSecondary)
}
