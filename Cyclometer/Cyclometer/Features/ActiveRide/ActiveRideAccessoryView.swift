import SwiftUI

/// S05.3 — the compact "mini-player" strip shown above the TabBar via
/// `tabViewBottomAccessory` while the Active Ride Dashboard is minimized.
/// Stateless display: it renders values passed by `AppView` and reports a tap
/// anywhere on the strip, which reopens the dashboard (#333, as Apple Music's mini
/// player does); the ride lifecycle lives in `AppFeature`/`ActiveRideFeature`.
struct ActiveRideAccessoryView: View {
    /// Route completion 0…1 (`NavigationFeature.State.routeProgressFraction`). `nil` → bicycle
    /// glyph: no route, turn-by-turn off, or no position on the route yet.
    let progress: Double?
    let distanceMeters: Double
    let speedMPS: Double
    let elapsedSeconds: Int
    let unit: UnitSystem
    let onOpen: () -> Void
    /// Forces the layout for a preview or snapshot. The placement environment value is
    /// get-only, so nothing outside a real tab bar can set it.
    var isCollapsedOverride: Bool? = nil

    /// `.inline` when the strip is collapsed into the TabBar (tabs scrolled),
    /// `.expanded` when shown full-width above it. Drives how much we can fit.
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    private var displayDistance: Double { unit.distance(fromMeters: distanceMeters) }
    private var displaySpeed: Double { unit.speed(fromMPS: speedMPS) }
    private var isCollapsed: Bool { isCollapsedOverride ?? (placement == .inline) }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: Spacing.xs) {
                OpenRingProgressView(progress: progress)
                    .frame(width: Spacing.xxxl, height: Spacing.xxxl) // 40pt ≈ S05.3 42pt

                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    HeroNumber(elapsedSeconds.formattedElapsed, unit: "").heroNumberSize(.small)
                    Spacer()
                    HeroNumber(displayDistance, unit: unit.distanceLabel).heroNumberSize(.small)
                    // Speed is dropped when collapsed into the TabBar — there isn't
                    // room, and the overflow reads as clipped/ugly.
                    if !isCollapsed {
                        Spacer()
                        HeroNumber(displaySpeed, unit: unit.speedLabel).heroNumberSize(.small)
                    }
                }
                Spacer()
            }
            // The Spacer's gap is part of the target too.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the ride dashboard")
    }
}

// MARK: - Previews

#Preview("No route (bicycle)") {
    ActiveRideAccessoryView(
        progress: nil, distanceMeters: 12300, speedMPS: 7.89, elapsedSeconds: 2340, unit: .imperial, onOpen: {}
    )
    .padding()
    .tint(.cyPrimary)   // AppView applies this globally on the TabView
}

#Preview("With route (metric)") {
    ActiveRideAccessoryView(
        progress: 0.42, distanceMeters: 12300, speedMPS: 7.89, elapsedSeconds: 2340, unit: .metric, onOpen: {}
    )
    .padding()
    .tint(.cyPrimary)   // AppView applies this globally on the TabView
}

/// Collapsed into the TabBar (`.inline`), where speed is dropped. The width
/// approximates the inline slot beside the minimised tab button on iPhone 17 Pro.
#Preview("Collapsed (inline)") {
    ActiveRideAccessoryView(
        progress: nil, distanceMeters: 12300, speedMPS: 7.89, elapsedSeconds: 2340, unit: .imperial,
        onOpen: {}, isCollapsedOverride: true
    )
    .frame(width: 300)
    .padding()
    .tint(.cyPrimary)   // AppView applies this globally on the TabView
}
