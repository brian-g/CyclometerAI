import SwiftUI

/// S22 — the ride's Live Activity on the Lock Screen (PRD §8.10, #309): the S05.3 mini-player's
/// status mark, elapsed time, distance and speed, with speed the largest (Sketch "S22 - Live
/// Activity"). Display only.
///
/// Compiled into the app, so it can be snapshot-tested, and into the `CyclometerWidgets`
/// extension, which draws it. The card behind it, `card(colorScheme:isLuminanceReduced:)`, is the
/// activity's background tint, `RideLiveActivity`'s job, since a view can't draw the Lock Screen's
/// own background.
struct RideLockScreenView: View {
    /// `cyBgPrimary` at `Opacity.liveActivityCard`: WCAG AA over any wallpaper
    /// (`LiveActivityContrastTests`). Dark on the Always-On display whatever the appearance. With
    /// no tint there, iOS draws a light glass of its own, and the units all but vanished on it
    /// (seen on the simulator, #309).
    static func card(colorScheme: ColorScheme, isLuminanceReduced: Bool) -> Color {
        var environment = EnvironmentValues()
        environment.colorScheme = isLuminanceReduced ? .dark : colorScheme
        return Color(Color.cyBgPrimary.resolve(in: environment)).opacity(Opacity.liveActivityCard)
    }

    let state: RideActivityAttributes.ContentState
    let units: UnitSystem
    /// `ActivityViewContext.isStale`: the app stopped updating, so the values may be old.
    let isStale: Bool

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.colorScheme) private var colorScheme

    private var valueColor: Color { isStale ? .cyTextSecondary : .cyTextPrimary }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.md) {
                RideStatusMark(state: state)
                    .frame(width: Spacing.xxxl, height: Spacing.xxxl)

                // First baselines: distance's unit sits under it (Sketch's `small-hero`), so its
                // last baseline is the unit's.
                HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                    // On the Lock Screen a `Text(timerInterval:)` takes far more width than it
                    // shows, pushing distance across the card (seen on the simulator). It's laid
                    // out as h:mm:ss instead, Sketch's slot, so nothing moves at the hour either.
                    HeroNumber(ElapsedTime.widest(state), unit: "")
                        .heroNumberSize(.small)
                        .hidden()
                        .overlay(alignment: .leading) {
                            HeroNumber(ElapsedTime.text(state), unit: "")
                                .heroNumberSize(.small)
                                .valueColor(valueColor)
                        }
                    HeroNumber(units.distance(fromMeters: state.distanceMeters), unit: units.distanceLabel)
                        .heroNumberSize(.small)
                        .layout(.vertical)
                        .valueColor(valueColor)
                    Spacer(minLength: 0)
                    HeroNumber(units.speed(fromMPS: state.speedMPS), unit: units.speedLabel)
                        .heroNumberSize(.medium)
                        .valueColor(valueColor)
                }
                .foregroundStyle(.cyTextSecondary)   // the units
            }

            if isStale {
                Text("Reconnecting…")
                    .font(.caption)
                    .foregroundStyle(.cyTextSecondary)
            }
        }
        .padding(Spacing.lg)
        // The Always-On display's card is always dark, so the text is white on it.
        .environment(\.colorScheme, isLuminanceReduced ? .dark : colorScheme)
    }
}

/// The pause icon while paused; otherwise the mini-player's ring, or its bicycle glyph with no
/// route. Also the Dynamic Island's minimal presentation.
struct RideStatusMark: View {
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

/// The ride's elapsed time: counts up from `startDate` on its own while riding, frozen while
/// paused. One timer for both, so the frozen value is formatted exactly as the running one.
enum ElapsedTime {
    /// The slot the timer is laid out in, as wide as any time it could show next. D-DIN's digits
    /// are proportional, with no tabular figures, and "4" is the widest. Two-digit hours from 9 h
    /// in, ahead of the tenth, since the timer ticks between updates.
    static func widest(_ state: RideActivityAttributes.ContentState) -> String {
        let elapsed = state.status == .paused
            ? state.pausedElapsed ?? 0
            : Date.now.timeIntervalSince(state.startDate)
        return elapsed < 9 * 3_600 ? "4:44:44" : "44:44:44"
    }

    static func text(_ state: RideActivityAttributes.ContentState) -> Text {
        let pauseTime = state.status == .paused
            ? state.pausedElapsed.map { state.startDate.addingTimeInterval($0) }
            : nil
        return Text(timerInterval: state.startDate...Date.distantFuture, pauseTime: pauseTime,
                    countsDown: false)
    }
}

// MARK: - Previews

private extension RideActivityAttributes.ContentState {
    static func sample(_ status: RideStatus = .riding, elapsed: TimeInterval = 2_340,
                       routeProgress: Double? = 0.42) -> Self {
        Self(status: status, startDate: .now.addingTimeInterval(-elapsed),
             pausedElapsed: status == .paused ? elapsed : nil,
             speedMPS: status == .paused ? 0 : 7.89, distanceMeters: 12_300, routeProgress: routeProgress)
    }
}

/// The view on its card, as the Lock Screen draws it.
private struct PreviewCard: View {
    let state: RideActivityAttributes.ContentState
    var units: UnitSystem = .metric
    var isStale = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        RideLockScreenView(state: state, units: units, isStale: isStale)
            .background(RideLockScreenView.card(colorScheme: colorScheme, isLuminanceReduced: isLuminanceReduced),
                        in: .rect(cornerRadius: Spacing.lg))
            .padding()
    }
}

#Preview("Route") { PreviewCard(state: .sample()) }
#Preview("Route (dark)") { PreviewCard(state: .sample()).preferredColorScheme(.dark) }
#Preview("No route (imperial)") { PreviewCard(state: .sample(routeProgress: nil), units: .imperial) }
#Preview("Paused, past the hour") { PreviewCard(state: .sample(.paused, elapsed: 17_084)) }
#Preview("Two-digit hours") { PreviewCard(state: .sample(.paused, elapsed: 36_000)) }
#Preview("Stale") { PreviewCard(state: .sample(.paused), isStale: true) }
#Preview("Always-On") { PreviewCard(state: .sample(.paused)).environment(\.isLuminanceReduced, true) }
