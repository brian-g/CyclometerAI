import ActivityKit
import SwiftUI
import WidgetKit

/// The ride on the Lock Screen and in the Dynamic Island (PRD §8.10). The Lock Screen is
/// `RideLockScreenView` (#309) on a `cyBgPrimary` card. The Dynamic Island (#310, Sketch "S22 -
/// Dynamic Island" and "S22 - Expanded Dynamic Island"): compact is the status mark and the speed,
/// minimal the status mark, expanded the Lock Screen's row with distance's unit beside it. The
/// island is always black, so its views take the dark scheme whatever the phone's appearance.
struct RideLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            LockScreenCard {
                RideLockScreenView(state: context.state, units: context.attributes.units,
                                   isStale: context.isStale)
                    .padding(Spacing.lg)
            }
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    RideLockScreenView(state: context.state, units: context.attributes.units,
                                       isStale: context.isStale, distanceLayout: .horizontal)
                        // `HeroNumber`'s digits and units hang past its frame, and the region's
                        // bottom corners are rounded: unpadded, "mph" was cut (simulator, #310).
                        .padding(.vertical, Spacing.sm)
                        .environment(\.colorScheme, .dark)
                }
            } compactLeading: {
                RideStatusMark(state: context.state, showsPercent: false)
                    .frame(width: Spacing.islandStatusMark, height: Spacing.islandStatusMark)
                    .environment(\.colorScheme, .dark)
            } compactTrailing: {
                RideIslandSpeed(state: context.state, units: context.attributes.units,
                                isStale: context.isStale)
                    .environment(\.colorScheme, .dark)
            } minimal: {
                RideStatusMark(state: context.state, showsPercent: false)
                    .frame(width: Spacing.islandStatusMark, height: Spacing.islandStatusMark)
                    .environment(\.colorScheme, .dark)
            }
            // Sketch's 15pt, near enough, for the Lock Screen card's padding. The system's ~18pt
            // left the row ~338pt, near its 337pt worst case (simulator, #310).
            .contentMargins(.horizontal, Spacing.lg, for: .expanded)
        }
    }
}

/// Tints the activity's background with `RideLockScreenView`'s card. The tint is the system's to
/// draw: it lives on the Lock Screen's own rounded shape, so this view draws none.
private struct LockScreenCard<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        content.activityBackgroundTint(
            RideLockScreenView.card(colorScheme: colorScheme, isLuminanceReduced: isLuminanceReduced)
        )
    }
}

// MARK: - Previews

private extension RideActivityAttributes.ContentState {
    static let riding = Self(status: .riding, startDate: .now.addingTimeInterval(-2_340), pausedElapsed: nil,
                             speedMPS: 7.89, distanceMeters: 12_300, routeProgress: 0.42)
    static let noRoute = Self(status: .riding, startDate: .now.addingTimeInterval(-2_340), pausedElapsed: nil,
                              speedMPS: 7.89, distanceMeters: 12_300, routeProgress: nil)
    /// Past the hour, where the timer gains a field.
    static let pastTheHour = Self(status: .riding, startDate: .now.addingTimeInterval(-5_674), pausedElapsed: nil,
                                  speedMPS: 12.4, distanceMeters: 48_700, routeProgress: 0.87)
    static let paused = Self(status: .paused, startDate: .now.addingTimeInterval(-5_674), pausedElapsed: 5_674,
                             speedMPS: 0, distanceMeters: 48_700, routeProgress: 0.87)
}

// Stale and reduced luminance come from the system (`isStale`, the Always-On display), so the
// canvas can't show them; `RideLockScreenSnapshotTests` covers both.
#Preview("Lock Screen", as: .content, using: RideActivityAttributes(units: .metric)) {
    RideLiveActivity()
} contentStates: {
    RideActivityAttributes.ContentState.riding
    RideActivityAttributes.ContentState.noRoute
    RideActivityAttributes.ContentState.pastTheHour
    RideActivityAttributes.ContentState.paused
}

#Preview("Lock Screen (imperial)", as: .content, using: RideActivityAttributes(units: .imperial)) {
    RideLiveActivity()
} contentStates: {
    RideActivityAttributes.ContentState.riding
    RideActivityAttributes.ContentState.paused
}

#Preview("Island compact", as: .dynamicIsland(.compact), using: RideActivityAttributes(units: .metric)) {
    RideLiveActivity()
} contentStates: {
    RideActivityAttributes.ContentState.riding
    RideActivityAttributes.ContentState.noRoute
    RideActivityAttributes.ContentState.paused
}

#Preview("Island expanded", as: .dynamicIsland(.expanded), using: RideActivityAttributes(units: .imperial)) {
    RideLiveActivity()
} contentStates: {
    RideActivityAttributes.ContentState.riding
    RideActivityAttributes.ContentState.noRoute
    RideActivityAttributes.ContentState.paused
}

#Preview("Island minimal", as: .dynamicIsland(.minimal), using: RideActivityAttributes(units: .metric)) {
    RideLiveActivity()
} contentStates: {
    RideActivityAttributes.ContentState.riding
    RideActivityAttributes.ContentState.noRoute
    RideActivityAttributes.ContentState.paused
}
