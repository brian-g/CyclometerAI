import ComposableArchitecture
import Foundation

/// PRD §8.10 (#308): keeps the ride's Live Activity showing what the S05.3 mini-player shows.
///
/// Layered onto `ActiveRideFeature`'s own domain rather than scoped to a child of it. It reads
/// the whole ride on each tick (status, elapsed time, speed, distance, navigation's progress),
/// and it ends the activity on the very action that tears the ride down: `AppFeature` nils
/// `activeRide` on `.confirmFinish`, so a child action forwarded from it would find no ride.
///
/// The ride's 1 Hz `.elapsedTick` is the throttle. Readings between two ticks fold into the
/// next one, so the activity gets at most one update a second, on the injected clock, and
/// nothing is sent ahead of a tick: a pause shows at the next one. Composed last in
/// `ActiveRideFeature.body`, so a tick's values are already in when it reads them.
@Reducer
struct LiveActivityFeature {
    typealias State = ActiveRideFeature.State
    typealias Action = ActiveRideFeature.Action

    /// An activity that hasn't changed is sent again after this many ticks, which moves its
    /// stale date on. A paused ride changes nothing, and would show as stale 30 s into a stop
    /// while the app is fine; a dead app sends nothing, so its activity still goes stale.
    static let keepAliveTicks = Int(LiveActivityClient.staleInterval / 2)

    @Dependency(\.liveActivityClient) var liveActivityClient
    @Dependency(\.date) var date

    private enum CancelID { case activityEnd }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task, .liveActivity(.appBecameActive):
                // A refused request (the app was in the background) or Live Activities switched
                // on mid-ride gets another go when the app comes forward, as does one the system
                // ended. One the rider swiped away is `.dismissed`, and isn't brought back.
                return start(&state)
            case .liveActivity(.preferenceChanged):
                // S12's toggle, mid-ride (#313): on starts one now, the app being in front; off
                // ends the one showing.
                guard !state.preferences.isLiveActivityEnabled else { return start(&state) }
                guard state.liveActivity.phase != .notShowing else { return .none }
                state.liveActivity = LiveActivityState()
                // The wait goes now, so this end can't come back as the rider's dismissal (#412).
                // A new wait's `cancelInFlight` would cancel it only once that wait's task runs.
                return .merge(
                    .cancel(id: CancelID.activityEnd),
                    .run { [liveActivityClient] _ in await liveActivityClient.end() }
                )
            case .liveActivity(.started(let isShowing)):
                // Turned off while the request was out: the client runs that `end` after the
                // request (#411), so the activity it showed is gone already.
                guard state.liveActivity.phase == .starting else { return .none }
                guard isShowing else {
                    state.liveActivity = LiveActivityState()
                    return .none
                }
                state.liveActivity = LiveActivityState(phase: .showing, shown: state.liveActivity.shown)
                // Watches for the system or the rider ending it outside the app (#412). One wait
                // at a time: a new activity's replaces the last one's.
                return .run { [liveActivityClient] send in
                    guard let end = await liveActivityClient.ended() else { return }
                    await send(.liveActivity(.ended(end)))
                }
                .cancellable(id: CancelID.activityEnd, cancelInFlight: true)
            case .liveActivity(.ended(let end)):
                // The app's own `end` comes back here as a dismissal too; the phase has moved on
                // by then, so it's dropped.
                guard state.liveActivity.phase == .showing else { return .none }
                // A swiped-away card stays gone. "Don't Allow" also switches Live Activities off,
                // and `start`'s `isEnabled()` holds it until the rider switches them back on.
                let isSwipedAway = end == .dismissed && liveActivityClient.isEnabled()
                state.liveActivity = isSwipedAway ? LiveActivityState(phase: .dismissed) : LiveActivityState()
                return .none
            case .elapsedTick:
                guard state.liveActivity.phase == .showing else { return .none }
                let content = Self.content(for: state, now: date.now)
                state.liveActivity.ticksSinceUpdate += 1
                guard content != state.liveActivity.shown
                        || state.liveActivity.ticksSinceUpdate >= Self.keepAliveTicks else { return .none }
                state.liveActivity.shown = content
                state.liveActivity.ticksSinceUpdate = 0
                return .run { [liveActivityClient] _ in await liveActivityClient.update(content) }
            case .finishAlert(.presented(.confirmFinish)):
                // An effect of the action that nils the ride, so `ifLet` doesn't cancel it.
                return .run { [liveActivityClient] _ in await liveActivityClient.end() }
            default:
                return .none
            }
        }
    }

    /// Requests the activity, when none is showing and both the system's setting and S12's allow it.
    private func start(_ state: inout State) -> Effect<Action> {
        guard state.liveActivity.phase == .notShowing,
              state.preferences.isLiveActivityEnabled,
              liveActivityClient.isEnabled() else { return .none }
        let attributes = RideActivityAttributes(units: state.unitSystem)
        let content = Self.content(for: state, now: date.now)
        state.liveActivity = LiveActivityState(phase: .starting, shown: content)
        return .run { [liveActivityClient] send in
            let isShowing = await liveActivityClient.start(attributes, content)
            await send(.liveActivity(.started(isShowing)))
        }
    }

    /// The mini-player's values, as `AppView` hands them to `ActiveRideAccessoryView`.
    ///
    /// While riding, `startDate` is `now − elapsedSeconds`, so the Lock Screen's timer reads what
    /// the dashboard does. Riding on, the one already shown is kept while it's within a second of
    /// that, so a steady ride doesn't send a new date every tick. A resume always gets a new one:
    /// it moves the start by the pause's length, which can be the very second the tolerance
    /// allows. While paused the shown one is kept and the timer shows `pausedElapsed` instead.
    static func content(for state: State, now: Date) -> RideActivityAttributes.ContentState {
        let elapsed = TimeInterval(state.elapsedSeconds)
        let shown = state.liveActivity.shown
        let ridingStart = now.addingTimeInterval(-elapsed)
        let startDate: Date
        if let shown, state.isPaused
            || (shown.status == .riding && abs(shown.startDate.timeIntervalSince(ridingStart)) <= 1) {
            startDate = shown.startDate
        } else {
            startDate = ridingStart
        }
        return RideActivityAttributes.ContentState(
            status: state.isPaused ? .paused : .riding,
            startDate: startDate,
            pausedElapsed: state.isPaused ? elapsed : nil,
            speedMPS: state.speedMPS,
            distanceMeters: state.distanceMeters,
            routeProgress: state.navigation.routeProgressFraction
        )
    }
}

/// The ride's Live Activity, as `LiveActivityFeature` last left it.
struct LiveActivityState: Equatable {
    enum Phase: Equatable {
        /// None requested, or the request was refused.
        case notShowing
        case starting
        case showing
        /// The rider swiped it away: not requested again this ride.
        case dismissed
    }

    var phase: Phase = .notShowing
    /// What the activity was last given.
    var shown: RideActivityAttributes.ContentState?
    /// Ticks since the last update, for the keep-alive.
    var ticksSinceUpdate = 0
}

@CasePathable
enum LiveActivityAction: Equatable {
    /// `start`'s answer: whether an activity is showing.
    case started(Bool)
    /// `ended`'s answer: the activity ended outside the app (#412).
    case ended(LiveActivityEnd)
    /// The app came to the foreground (`AppFeature`).
    case appBecameActive
    /// S12's Show Live Activity changed (`AppFeature`, #313).
    case preferenceChanged
}
