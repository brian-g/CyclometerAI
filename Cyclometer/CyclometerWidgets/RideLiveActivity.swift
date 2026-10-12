import ActivityKit
import SwiftUI
import WidgetKit

/// The ride on the Lock Screen and in the Dynamic Island (PRD §8.10). The Lock Screen is
/// `RideLockScreenView` (#309) on a `cyBgPrimary` card; the Dynamic Island is still #306's
/// placeholder, pending #310.
struct RideLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            LockScreenCard {
                RideLockScreenView(state: context.state, units: context.attributes.units,
                                   isStale: context.isStale)
            }
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    ElapsedTime.text(context.state).monospacedDigit()
                }
            } compactLeading: {
                ElapsedTime.text(context.state).monospacedDigit()
            } compactTrailing: {
                Text(context.attributes.units.speed(fromMPS: context.state.speedMPS),
                     format: .number.precision(.fractionLength(0)))
            } minimal: {
                RideStatusMark(state: context.state)
            }
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
}

#Preview("Island minimal", as: .dynamicIsland(.minimal), using: RideActivityAttributes(units: .metric)) {
    RideLiveActivity()
} contentStates: {
    RideActivityAttributes.ContentState.riding
    RideActivityAttributes.ContentState.paused
}
