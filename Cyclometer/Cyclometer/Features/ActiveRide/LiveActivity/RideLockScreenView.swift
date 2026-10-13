import SwiftUI

/// S22 — the ride's Live Activity on the Lock Screen (PRD §8.10, #309): the status mark, elapsed
/// time, distance and speed, the S05.3 mini-player's content, with speed the largest (Sketch "S22 -
/// Live Activity"). Display only. The expanded Dynamic Island shows it too (#310).
///
/// Compiled into the app, so it can be snapshot-tested, and into the `CyclometerWidgets`
/// extension, which draws it. It has no margins of its own: `RideLiveActivity` sets them for the
/// Lock Screen and for the expanded Dynamic Island, which shows it too (#310). The card behind
/// it, `card(colorScheme:isLuminanceReduced:)`, is the activity's background tint,
/// `RideLiveActivity`'s job, since a view can't draw the Lock Screen's own background.
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
    /// Distance's unit under it on the Lock Screen (Sketch's `small-hero`); beside it in the
    /// expanded Dynamic Island (`small-hero-h`, #310). Beside it only while the row fits: Sketch's
    /// values do, but a metric or long ride runs 8–17pt over the island, so the unit drops under
    /// distance rather than truncating speed (asked).
    var distanceLayout: HeroUnitAlignment = .vertical

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.colorScheme) private var colorScheme

    private var valueColor: Color { isStale ? .cyTextSecondary : .cyTextPrimary }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.md) {
                RideStatusMark(state: state)
                    .frame(width: Spacing.xxxl, height: Spacing.xxxl)

                ViewThatFits(in: .horizontal) {
                    metrics(distanceLayout)
                    if distanceLayout != .vertical {
                        metrics(.vertical)
                    }
                }
                .foregroundStyle(.cyTextSecondary)   // the units
            }

            if isStale {
                Text("Reconnecting…")
                    .font(.caption)
                    .foregroundStyle(.cyTextSecondary)
            }
        }
        // The Always-On display's card is always dark, so the text is white on it.
        .environment(\.colorScheme, isLuminanceReduced ? .dark : colorScheme)
    }

    /// Time, distance and speed. First baselines: with distance's unit under it, its last baseline
    /// is the unit's.
    private func metrics(_ distanceLayout: HeroUnitAlignment) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
            // On the Lock Screen a `Text(timerInterval:)` takes far more width than it shows,
            // pushing distance across the card (seen on the simulator). It's laid out as h:mm:ss
            // instead, Sketch's slot, so nothing moves at the hour either.
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
                .layout(distanceLayout)
                .valueColor(valueColor)
            Spacer(minLength: 0)
            HeroNumber(units.speed(fromMPS: state.speedMPS), unit: units.speedLabel)
                .heroNumberSize(.medium)
                .valueColor(valueColor)
        }
    }
}

/// The pause icon while paused; otherwise the mini-player's route ring, or the app's rider glyph
/// with no route (Sketch "S22 - Dynamic Island", #310). Also the Dynamic Island's compact leading
/// and minimal presentations, where it's too small for the ring's percentage.
struct RideStatusMark: View {
    let state: RideActivityAttributes.ContentState
    var showsPercent = true

    var body: some View {
        if state.status == .paused {
            Image(systemName: "pause.circle.fill")
                .font(.title3)
                .foregroundStyle(.cyPrimary)
                // A state, not the symbol's "Pause", which sounds like a button.
                .accessibilityLabel("Paused")
        } else if let progress = state.routeProgress {
            OpenRingProgressView(progress: progress, showsPercent: showsPercent)
        } else {
            // Sized to the mark, not by font: the glyph is wider than a system symbol, and the
            // mark is 40pt on the Lock Screen but 26pt in the island.
            Image("cyclometer.rider")
                .resizable()
                .scaledToFit()
                .padding(Spacing.xs)
                .foregroundStyle(.cyPrimary)
                // The minimal island shows nothing else, so the mark has to say something.
                .accessibilityLabel("Riding")
        }
    }
}

/// The Dynamic Island's compact trailing side (#310): the speed alone, without its unit, in Sketch's
/// SF Pro Medium 18. System type, not `HeroNumber`: D-DIN's smallest hero is 34pt, twice the island.
/// Dims when stale, as the Lock Screen's values do.
struct RideIslandSpeed: View {
    /// Sketch "S22 - Dynamic Island".
    private static let fontSize: CGFloat = 18

    let state: RideActivityAttributes.ContentState
    let units: UnitSystem
    let isStale: Bool

    var body: some View {
        Text(units.speed(fromMPS: state.speedMPS), format: .number.precision(.fractionLength(0)))
            .font(.system(size: Self.fontSize, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(isStale ? .cyTextSecondary : .cyTextPrimary)
            // The unit isn't shown, so it's spoken; so is the Lock Screen's "Reconnecting…".
            .accessibilityLabel("Speed, \(units.spokenSpeed(fromMPS: state.speedMPS))")
            .accessibilityValue(isStale ? "Reconnecting" : "")
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

// The views alone, for the states the Live Activity canvas can't produce (stale, the Always-On
// display). `RideLiveActivity`'s previews show them in the system's presentations.
private extension RideActivityAttributes.ContentState {
    static func preview(status: RideStatus = .riding, routeProgress: Double? = 0.42) -> Self {
        let elapsed: TimeInterval = 5_674
        return Self(status: status, startDate: .now.addingTimeInterval(-elapsed),
                    pausedElapsed: status == .paused ? elapsed : nil,
                    speedMPS: status == .paused ? 0 : 7.89, distanceMeters: 25_270,
                    routeProgress: routeProgress)
    }
}

private struct LockScreenPreview: View {
    var state = RideActivityAttributes.ContentState.preview()
    var isStale = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        RideLockScreenView(state: state, units: .imperial, isStale: isStale)
            .padding(Spacing.lg)
            .background(RideLockScreenView.card(colorScheme: colorScheme, isLuminanceReduced: isLuminanceReduced))
            .padding()
            .background(Color.blue)
    }
}

/// The island's views on its black, in the dark scheme, as `RideLiveActivity` draws them.
private struct IslandPreview: View {
    var state = RideActivityAttributes.ContentState.preview()
    var isStale = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            HStack {
                RideStatusMark(state: state, showsPercent: false)
                    .frame(width: Spacing.islandStatusMark, height: Spacing.islandStatusMark)
                Spacer()
                RideIslandSpeed(state: state, units: .imperial, isStale: isStale)
            }
            .padding(.horizontal, Spacing.sm)
            .frame(width: 200, height: Spacing.dynamicIsland)
            .background(.black, in: .capsule)

            RideLockScreenView(state: state, units: .imperial, isStale: isStale, distanceLayout: .horizontal)
                .padding(Spacing.lg)
                .background(.black, in: .rect(cornerRadius: Spacing.xl))
        }
        .environment(\.colorScheme, .dark)
        .padding()
    }
}

#Preview("Lock Screen route") { LockScreenPreview() }
#Preview("Lock Screen no route") { LockScreenPreview(state: .preview(routeProgress: nil)) }
#Preview("Lock Screen paused") { LockScreenPreview(state: .preview(status: .paused)) }
#Preview("Lock Screen stale") { LockScreenPreview(isStale: true) }
#Preview("Lock Screen dark") { LockScreenPreview().preferredColorScheme(.dark) }
#Preview("Lock Screen Always-On") { LockScreenPreview().environment(\.isLuminanceReduced, true) }

#Preview("Island route") { IslandPreview() }
#Preview("Island no route") { IslandPreview(state: .preview(routeProgress: nil)) }
#Preview("Island paused") { IslandPreview(state: .preview(status: .paused)) }
#Preview("Island stale") { IslandPreview(isStale: true) }
