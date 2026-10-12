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

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task, .liveActivity(.appBecameActive):
                // A refused request (the app was in the background) or Live Activities switched
                // on mid-ride gets another go when the app comes forward. One the rider swiped
                // away stays `.showing`, and isn't brought back.
                guard state.liveActivity.phase == .notShowing, liveActivityClient.isEnabled() else {
                    return .none
                }
                let attributes = RideActivityAttributes(units: state.unitSystem)
                let content = Self.content(for: state, now: date.now)
                state.liveActivity = LiveActivityState(phase: .starting, shown: content)
                return .run { [liveActivityClient] send in
                    let isShowing = await liveActivityClient.start(attributes, content)
                    await send(.liveActivity(.started(isShowing)))
                }
            case .liveActivity(.started(let isShowing)):
                guard state.liveActivity.phase == .starting else { return .none }
                state.liveActivity = isShowing
                    ? LiveActivityState(phase: .showing, shown: state.liveActivity.shown)
                    : LiveActivityState()
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

    /// The mini-player's values, as `AppView` hands them to `ActiveRideAccessoryView`.
    ///
    /// While riding, `startDate` is `now − elapsedSeconds`, so the Lock Screen's timer reads what
    /// the dashboard does. The one already shown is kept while it's within a second of that:
    /// a steady ride doesn't send a new date every tick, and a resume, which moves it by the
    /// pause's length, gets a new one. While paused the shown one is kept and the timer shows
    /// `pausedElapsed` instead.
    static func content(for state: State, now: Date) -> RideActivityAttributes.ContentState {
        let elapsed = TimeInterval(state.elapsedSeconds)
        let shownStart = state.liveActivity.shown?.startDate
        let ridingStart = now.addingTimeInterval(-elapsed)
        let startDate: Date
        if state.isPaused, let shownStart {
            startDate = shownStart
        } else if let shownStart, abs(shownStart.timeIntervalSince(ridingStart)) <= 1 {
            startDate = shownStart
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
    /// The app came to the foreground (`AppFeature`).
    case appBecameActive
}
