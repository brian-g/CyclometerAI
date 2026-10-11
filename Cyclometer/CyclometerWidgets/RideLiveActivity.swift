import ActivityKit
import SwiftUI
import WidgetKit

/// The ride on the Lock Screen and in the Dynamic Island (PRD §8.10). A placeholder for #306:
/// it shows the S05.3 mini-player's content from shared code so the extension builds and
/// renders. The Lock Screen design is #309, the Dynamic Island's #310.
struct RideLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            HStack(spacing: Spacing.sm) {
                RideStatusMark(state: context.state)
                    .frame(width: Spacing.xxxl, height: Spacing.xxxl)
                ElapsedTime(state: context.state)
                Spacer()
                HeroNumber(context.attributes.units.distance(fromMeters: context.state.distanceMeters),
                           unit: context.attributes.units.distanceLabel)
                    .heroNumberSize(.small)
                HeroNumber(context.attributes.units.speed(fromMPS: context.state.speedMPS),
                           unit: context.attributes.units.speedLabel)
                    .heroNumberSize(.small)
            }
            .padding(Spacing.lg)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    ElapsedTime(state: context.state)
                }
            } compactLeading: {
                ElapsedTime(state: context.state)
            } compactTrailing: {
                Text(context.attributes.units.speed(fromMPS: context.state.speedMPS),
                     format: .number.precision(.fractionLength(0)))
            } minimal: {
                RideStatusMark(state: context.state)
            }
        }
    }
}

/// The pause icon while paused; otherwise the mini-player's ring, or its bicycle glyph with no route.
private struct RideStatusMark: View {
    let state: RideActivityAttributes.ContentState

    var body: some View {
        if state.status == .paused {
            Image(systemName: "pause.circle.fill")
                .font(.title3)
                .foregroundStyle(.cyPrimary)
        } else {
            OpenRingProgressView(progress: state.routeProgress)
        }
    }
}

/// Counts up from `startDate` on its own while riding; frozen while paused.
private struct ElapsedTime: View {
    let state: RideActivityAttributes.ContentState

    var body: some View {
        if state.status == .paused, let paused = state.pausedElapsed {
            Text(Duration.seconds(paused), format: .time(pattern: .minuteSecond))
                .monospacedDigit()
        } else {
            Text(timerInterval: state.startDate...Date.distantFuture, countsDown: false)
                .monospacedDigit()
        }
    }
}

// MARK: - Previews

private extension RideActivityAttributes.ContentState {
    static let riding = Self(status: .riding, startDate: .now.addingTimeInterval(-2_340), pausedElapsed: nil,
                             speedMPS: 7.89, distanceMeters: 12_300, routeProgress: 0.42)
    static let noRoute = Self(status: .riding, startDate: .now.addingTimeInterval(-2_340), pausedElapsed: nil,
                              speedMPS: 7.89, distanceMeters: 12_300, routeProgress: nil)
    static let paused = Self(status: .paused, startDate: .now.addingTimeInterval(-2_340), pausedElapsed: 2_340,
                             speedMPS: 0, distanceMeters: 12_300, routeProgress: 0.42)
}

#Preview("Lock Screen", as: .content, using: RideActivityAttributes(units: .metric)) {
    RideLiveActivity()
} contentStates: {
    RideActivityAttributes.ContentState.riding
    RideActivityAttributes.ContentState.noRoute
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
