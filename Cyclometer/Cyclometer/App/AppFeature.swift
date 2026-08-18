import ComposableArchitecture
import SwiftData

/// Root feature — owns tab selection and active ride lifecycle.
/// Navigation follows Apple Music pattern: Rides / Routes / Settings tabs.
/// Active ride dashboard is a custom screen over the tab structure.
@Reducer
struct AppFeature {

    /// Idle time on the dashboard before the display dims (#110). iOS exposes no
    /// public API for the system Auto-Lock interval, so this is a fixed value rather
    /// than a mirror of it. Moves to `AppPreferences` when it becomes a rider setting.
    static let dimAfterSeconds = 30

    /// Backlight level the dim drops to, 0…1 — the "amount to dim", and the other
    /// half of the future `AppPreferences` pair.
    static let dimBrightness: Double = 0.1

    @Dependency(\.bleCSCClient) var bleCSCClient
    @Dependency(\.variaRadarClient) var variaRadarClient
    @Dependency(\.bleHRClient) var bleHRClient
    @Dependency(\.screenClient) var screenClient
    @Dependency(\.continuousClock) var clock

    @ObservableState
    struct State: Equatable {
        @SharedReader(.appPreferences) var preferences
        var selectedTab: Tab = .rides
        var activeRide: ActiveRideFeature.State? = nil
        @Presents var startSheet: StartSheetFeature.State? = nil
        var isDashboardPresented: Bool = false
        var rides: RidesFeature.State = RidesFeature.State()
        var routes: RoutesFeature.State = RoutesFeature.State()
        var settings: SettingsFeature.State = SettingsFeature.State()

        // ── Screen power management (#110) ───────────────────────────────────────
        var isForeground: Bool = true
        var isDimmed: Bool = false
        /// The rider's own backlight level, captured when the dim starts so waking
        /// restores what they had rather than some app-chosen constant.
        var preDimBrightness: Double? = nil

        /// The app owns the display only while the dashboard is the visible surface
        /// and the app is foregrounded (#110). A ride minimized to the accessory pill
        /// deliberately does not count — the rider isn't reading it, so the phone
        /// should auto-lock as usual.
        var isDashboardVisible: Bool {
            isDashboardPresented && activeRide != nil && isForeground
        }
    }

    enum Tab: Hashable {
        case rides, routes, settings
    }

    enum Action {
        case task
        case tabSelected(Tab)
        case startRideButtonTapped
        case startSheet(PresentationAction<StartSheetFeature.Action>)
        case dashboardDismissed
        case dashboardOpened
        case rideFinished
        case rides(RidesFeature.Action)
        case routes(RoutesFeature.Action)
        case settings(SettingsFeature.Action)
        case activeRide(ActiveRideFeature.Action)

        // ── Screen power management (#110) ───────────────────────────────────────
        case scenePhaseChanged(isActive: Bool)
        case screenVisibilityChanged(Bool)
        /// Any touch on the dashboard — including the one that wakes it from a dim.
        /// The blocker overlay swallows that first touch, but where it came from is a
        /// view concern; the reducer only needs to know the rider is still there.
        case userInteracted
        case dimTimerFired
        case preDimBrightnessCaptured(Double)
    }

    private enum CancelID { case dimTimer }

    var body: some ReducerOf<Self> {
        Scope(state: \.rides,    action: \.rides)    { RidesFeature() }
        Scope(state: \.routes,   action: \.routes)   { RoutesFeature() }
        Scope(state: \.settings, action: \.settings) { SettingsFeature() }

        Reduce { state, action in
            switch action {
            case .task:
                // The clients hold no persistence, so the rider's pairings have to be
                // handed to them before any scan can act on them. Here rather than in
                // DeviceManagementFeature: sensors must reconnect on launch, not only
                // while the Sensors screen happens to be open.
                //
                // Pushing nil is meaningful, not a no-op skipped for tidiness: these
                // client state objects are process-global, so nil is how a gate left
                // open by an earlier state gets closed.
                //
                // Sequential rather than merged — a deterministic order is what makes
                // the launch push assertable as one interleaved call log (BLE.md §5.0).
                return .run { [
                    bleCSCClient, variaRadarClient, bleHRClient,
                    assignments = state.preferences.cscAssignments,
                    radarID = state.preferences.pairedSensor(for: .radar)?.peripheralID,
                    hrID = state.preferences.pairedSensor(for: .heartRate)?.peripheralID
                ] _ in
                    await bleCSCClient.setPairedSensors(assignments)
                    await variaRadarClient.setPairedSensor(radarID)
                    await bleHRClient.setPairedSensor(hrID)
                }

            case .tabSelected(let tab):
                state.selectedTab = tab
                return .none

            case .startRideButtonTapped:
                state.startSheet = StartSheetFeature.State()
                return .none

            case .startSheet(.presented(.delegate(.startRide))):
                state.activeRide = ActiveRideFeature.State()
                state.startSheet = nil
                state.isDashboardPresented = true
                state.selectedTab = .rides
                // Start the ride's long-running effects (1 Hz timer, HR, radar,
                // location) here so they live for the whole ride — bound to
                // `activeRide` via `.ifLet` and torn down only when the ride
                // ends. Previously this was driven by RideDashboardView's
                // `.task`, so minimizing the dashboard cancelled the timer.
                return .send(.activeRide(.task))

            case .startSheet:
                return .none

            case .dashboardDismissed:
                state.isDashboardPresented = false
                return .none

            case .dashboardOpened:
                if state.activeRide != nil { state.isDashboardPresented = true }
                return .none

            case .rideFinished:
                // TODO: persist ride summary to SwiftData before clearing state (M7).
                state.activeRide = nil
                state.isDashboardPresented = false
                return .none

            case .activeRide(.finishAlert(.presented(.confirmFinish))):
                state.activeRide = nil
                state.isDashboardPresented = false
                return .none

            case .scenePhaseChanged(let isActive):
                state.isForeground = isActive
                return .none

            case .screenVisibilityChanged(let isVisible):
                guard isVisible else {
                    // Everything the app took from the system goes back here, in one
                    // place: the idle timer, the pending timer, and the backlight.
                    return .merge(
                        .run { [screenClient] _ in await screenClient.setIdleTimerDisabled(false) },
                        .cancel(id: CancelID.dimTimer),
                        wake(&state)
                    )
                }
                return .merge(
                    .run { [screenClient] _ in await screenClient.setIdleTimerDisabled(true) },
                    armDimTimer(state)
                )

            case .userInteracted:
                guard state.isDashboardVisible else { return .none }
                // Sequenced, not inlined into `.merge`: `wake` takes `state` inout, so
                // reading it again in the same call would overlap that access.
                let restore = wake(&state)
                return .merge(restore, armDimTimer(state))

            case .dimTimerFired:
                guard state.isDashboardVisible, !state.isDimmed else { return .none }
                // Reading the backlight is async, so the dim commits in the *next*
                // action rather than here. That keeps `isDimmed` and
                // `preDimBrightness` inseparable — a dim that is on with nothing to
                // restore to is exactly the state that would strand the rider's phone
                // at 10% brightness.
                return .run { [screenClient] send in
                    await send(.preDimBrightnessCaptured(screenClient.brightness()))
                }

            case .preDimBrightnessCaptured(let level):
                // Re-checked, not assumed: the rider may have backgrounded the app or
                // minimized the dashboard while the read was in flight.
                guard state.isDashboardVisible, !state.isDimmed else { return .none }
                state.isDimmed = true
                state.preDimBrightness = level
                return .run { [screenClient] _ in
                    // Clamped, so a rider already riding at 5% is left at 5% rather
                    // than being *brightened* to the dim level.
                    await screenClient.setBrightness(min(level, Self.dimBrightness))
                }

            case .rides, .routes, .settings, .activeRide:
                return .none
            }
        }
        // The inputs to `isDashboardVisible` change from several places, but the
        // derived value flips rarely — so screen ownership is forwarded on the
        // transition rather than recomputed at every call site.
        .onChange(of: \.isDashboardVisible) { _, isVisible in
            Reduce { _, _ in
                .send(.screenVisibilityChanged(isVisible))
            }
        }
        .ifLet(\.activeRide, action: \.activeRide) {
            ActiveRideFeature()
        }
        .ifLet(\.$startSheet, action: \.startSheet) {
            StartSheetFeature()
        }
    }

    /// Restores the rider's own brightness and clears the dim. A no-op when not
    /// dimmed, which is what lets every "the app no longer owns the screen" path call
    /// it unconditionally instead of each one re-deriving whether it needs to.
    private func wake(_ state: inout State) -> Effect<Action> {
        guard state.isDimmed, let restore = state.preDimBrightness else { return .none }
        state.isDimmed = false
        state.preDimBrightness = nil
        return .run { [screenClient] _ in await screenClient.setBrightness(restore) }
    }

    /// `cancelInFlight` is what makes restarting on every touch cheap — the previous
    /// countdown is torn down rather than racing the new one.
    ///
    /// Gated on the rider's Auto-dim preference (S12). The wake lock deliberately is
    /// not — turning auto-dim off means "stop dimming", not "let the phone sleep
    /// mid-ride".
    private func armDimTimer(_ state: State) -> Effect<Action> {
        guard state.preferences.isAutoDimEnabled else { return .none }
        return .run { [clock] send in
            try await clock.sleep(for: .seconds(Self.dimAfterSeconds))
            await send(.dimTimerFired)
        }
        .cancellable(id: CancelID.dimTimer, cancelInFlight: true)
    }
}
