import ComposableArchitecture
import Foundation
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
    @Dependency(\.persistenceClient) var persistenceClient
    @Dependency(\.rideEndIntentClient) var rideEndIntentClient
    @Dependency(\.date) var date

    @ObservableState
    struct State: Equatable {
        @SharedReader(.appPreferences) var preferences
        var selectedTab: Tab = .rides
        var activeRide: ActiveRideFeature.State? = nil
        @Presents var startSheet: StartSheetFeature.State? = nil
        var onboarding: OnboardingFeature.State? = nil
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

        /// The app owns the display only while the dashboard is the visible surface,
        /// a ride is actively recording, and the app is foregrounded (#110, #102). A
        /// ride minimized to the accessory pill deliberately does not count — the
        /// rider isn't reading it, so the phone should auto-lock as usual. Nor does a
        /// paused ride: the wake lock and any in-progress dim release the moment the
        /// rider stops, the same as ending the ride or backgrounding the app.
        var isDashboardVisible: Bool {
            isDashboardPresented && activeRide?.recordingState == .active && isForeground
        }
    }

    enum Tab: Hashable {
        case rides, routes, settings
    }

    enum Action {
        case task
        case tabSelected(Tab)
        /// A `.gpx` handed over by Files, Mail or Safari (`CFBundleDocumentTypes`), which
        /// the app imports through the same path as the in-app picker.
        case fileOpened(URL)
        case startRideButtonTapped
        case startSheet(PresentationAction<StartSheetFeature.Action>)
        case onboarding(OnboardingFeature.Action)
        case dashboardDismissed
        case dashboardOpened
        case rides(RidesFeature.Action)
        case routes(RoutesFeature.Action)
        case settings(SettingsFeature.Action)
        case activeRide(ActiveRideFeature.Action)
        /// Sent from `.task` when a kill mid-ride left a non-`.ended` Ride behind
        /// (#175).
        case resumableRideFetched(RideSummaryUpdate)

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
                // Presented until the rider completes it; never reconstructed once
                // `hasCompletedOnboarding` is true, regardless of what permissions do
                // afterward (#105).
                if !state.preferences.hasCompletedOnboarding && state.onboarding == nil {
                    state.onboarding = OnboardingFeature.State(
                        step: state.preferences.hasCompletedWelcomeStep ? .sensorPairing : .welcome
                    )
                }

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
                //
                // Merged with the resume-fetch below: the two are independent
                // concerns (unlike the three sequential calls inside the first
                // effect, which must run in a fixed order relative to each other).
                return .merge(
                    .run { [
                        bleCSCClient, variaRadarClient, bleHRClient,
                        assignments = state.preferences.cscAssignments,
                        radarID = state.preferences.pairedSensor(for: .radar)?.peripheralID,
                        hrID = state.preferences.pairedSensor(for: .heartRate)?.peripheralID
                    ] _ in
                        await bleCSCClient.setPairedSensors(assignments)
                        await variaRadarClient.setPairedSensor(radarID)
                        await bleHRClient.setPairedSensor(hrID)
                    },
                    // #175: at most one non-ended Ride can exist; if a kill left one
                    // behind, resume it instead of leaving it permanently orphaned.
                    .run { [persistenceClient] send in
                        if let summary = try? await persistenceClient.fetchResumableRide() {
                            await send(.resumableRideFetched(summary))
                        } else {
                            // Retries any thumbnail a past Finish failed to capture (#177).
                            // Only here: a ride closed out by `resumableRideFetched` runs
                            // the backfill itself once its finalize lands, so the two never
                            // race over the same ride.
                            await Self.backfillMapThumbnails(send: send)
                        }
                    }
                )

            case .tabSelected(let tab):
                state.selectedTab = tab
                return .none

            case .fileOpened(let url):
                // GPX is the only declared document type, so anything arriving here is a
                // route. A non-file URL would be a custom scheme the app doesn't register.
                guard url.isFileURL else { return .none }
                state.selectedTab = .routes
                // Straight to the list: a route detail left on the stack would hide the row
                // the import is about to insert, and the failure alert with it.
                state.routes.path.removeAll()
                // Forwarded rather than reimplemented — `.fileSelected` owns the
                // security-scoped read, the re-entrancy guard and both alert paths, and an
                // in-place open is scoped exactly like a picked file.
                return .send(.routes(.fileSelected(url)))

            case .startRideButtonTapped:
                return presentStartSheet(&state)

            case .startSheet(.dismiss):
                // Cancel and swipe-to-dismiss both arrive here. The route goes with the sheet's own
                // state, so the next Start Ride opens on a free ride (#196).
                return Self.endStartSheetScan(bleCSCClient, variaRadarClient, bleHRClient)

            case .startSheet(.presented(.delegate(.startRide(let route)))):
                // Never start a second ride over a live one (#231). `resumableRideFetched`
                // dismisses the sheet, which stops this delegate being *emitted* — it
                // originates inside the child (`StartSheetFeature.startRideButtonTapped`),
                // so nil state means no delegate. But that is a fact about where the action
                // comes from, not a guarantee from the framework: TCA skips only the *child*
                // reducer for a presented action against absent state and still runs this
                // one (`PresentationReducer`, `case (.none, .some)`). The day the sheet emits
                // this from an effect that awaits anything, the unguarded version silently
                // replaces the resumed ride and double-releases the scan.
                guard state.activeRide == nil else { return .none }
                // The sheet's route is what the ride writes to its `Ride` (#196).
                Self.presentActiveRide(ActiveRideFeature.State(route: route), in: &state)
                state.startSheet = nil
                // Start the ride's long-running effects (1 Hz timer, HR, radar,
                // location) here so they live for the whole ride — bound to
                // `activeRide` via `.ifLet` and torn down only when the ride
                // ends. Previously this was driven by RideDashboardView's
                // `.task`, so minimizing the dashboard cancelled the timer.
                // The sheet is going away without a `.dismiss`, so its scan is released
                // here. The ride takes its own scan in `activeRide(.task)`, and the
                // refcount never reaches zero in between — the connections the sheet
                // established stay up.
                return .merge(
                    Self.endStartSheetScan(bleCSCClient, variaRadarClient, bleHRClient),
                    .send(.activeRide(.task))
                )

            case .startSheet:
                return .none

            case .dashboardDismissed:
                state.isDashboardPresented = false
                return .none

            case .dashboardOpened:
                if state.activeRide != nil { state.isDashboardPresented = true }
                return .none

            case .activeRide(.finishAlert(.presented(.confirmFinish))):
                let finishedRideId = state.activeRide?.rideId
                state.activeRide = nil
                state.isDashboardPresented = false
                // The Rides tab only loads on its own `.task`, which fires once when it
                // first mounts — not when a ride finishes underneath an already-mounted
                // tab. Without this, the just-finished ride is invisible until something
                // else (a tab switch) tears the view down and remounts it. `rideFinished`,
                // not `reloadRides`: ActiveRideFeature's own finish effect (flush → GPX
                // export → finalizeRide) is a separate effect racing this one, so the
                // write is very often still in flight at this exact moment.
                guard let finishedRideId else { return .none }
                return .send(.rides(.rideFinished(finishedRideId)))

            case .resumableRideFetched(let summary):
                // `.task`'s two effects race: the rider can start a brand-new ride
                // through the normal start-sheet flow before this async fetch
                // resolves. Don't clobber that ride — but the orphaned one still
                // needs to be closed out, or it stays a phantom non-`.ended` row
                // forever (invisible in RidesView, never exported) (#175 review).
                guard state.activeRide == nil else {
                    return .run { [persistenceClient, date] send in
                        try? await persistenceClient.finalizeRide(summary.rideId, date.now, summary, nil)
                        await send(.rides(.reloadRides))
                        await Self.backfillMapThumbnails(send: send)
                    }
                }

                // The rider already ended this ride and only its finalize write failed,
                // so it is resumable purely because `endedAt` never got set. Close it
                // out instead of resuming a ride that is over (#188) — otherwise the
                // recorder restarts and sensors reconnect on a finished ride.
                if let pending = rideEndIntentClient.load(), pending.rideId == summary.rideId {
                    return .run { [persistenceClient, rideEndIntentClient] send in
                        do {
                            try await persistenceClient.finalizeRide(
                                pending.rideId, pending.endedAt, summary, pending.gpxFileURL
                            )
                            rideEndIntentClient.clear()
                            await send(.rides(.reloadRides))
                            await Self.backfillMapThumbnails(send: send)
                        } catch {
                            // Logged in RidePersistenceActor. The marker stays so the
                            // next launch tries again rather than resuming the ride.
                        }
                    }
                }

                // The rider can have S05.1 open when this lands — the fetch races the UI —
                // and a sheet offering to start a ride they are already on is not a state
                // to leave them in: tapping its Start Ride would replace the resumed ride
                // without finalizing it, orphaning that Ride row forever (#231). Nil'ing
                // the sheet here is what makes the two unrepresentable together: the
                // start-ride delegate is only ever emitted from inside the child, so an
                // absent sheet cannot produce one. The delegate case guards on
                // `activeRide` as well, because that is a property of where the action
                // originates rather than something the framework enforces.
                //
                // Read before the nil, and only released if a sheet was actually up:
                // `endStartSheetScan` unconditionally would drive the refcount below zero
                // on the ordinary launch path, where no sheet ever took a scan.
                let releaseStartSheetScan = state.startSheet != nil
                    ? Self.endStartSheetScan(bleCSCClient, variaRadarClient, bleHRClient)
                    : .none
                state.startSheet = nil
                Self.presentActiveRide(ActiveRideFeature.State(resuming: summary), in: &state)
                return .merge(releaseStartSheetScan, .send(.activeRide(.task)))

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

            case .onboarding(.delegate(.completed)):
                // The two preference writes happen inside `OnboardingFeature`, which owns
                // both fields; this only clears the presentation.
                state.onboarding = nil
                return .none

            case .routes(.delegate(.useRoute(let route))):
                return presentStartSheet(&state, route: route)

            case .rides, .routes, .settings, .activeRide, .onboarding:
                return .none
            }
        }
        .ifLet(\.activeRide, action: \.activeRide) {
            ActiveRideFeature()
        }
        .ifLet(\.$startSheet, action: \.startSheet) {
            StartSheetFeature()
        }
        .ifLet(\.onboarding, action: \.onboarding) {
            OnboardingFeature()
        }
        // The inputs to `isDashboardVisible` change from several places, but the
        // derived value flips rarely — so screen ownership is forwarded on the
        // transition rather than recomputed at every call site. Placed after both
        // `.ifLet`s (#102): `recordingState` is mutated inside `ActiveRideFeature`,
        // so `.onChange` has to wrap that reducer too, or a pause/resume/end
        // reaching the child via `.ifLet` would go unobserved here.
        .onChange(of: \.isDashboardVisible) { _, isVisible in
            Reduce { _, _ in
                .send(.screenVisibilityChanged(isVisible))
            }
        }
    }

    /// Puts a ride's dashboard on screen — shared by starting a brand-new ride
    /// and resuming one found on relaunch (#175), so a future addition to
    /// "present the ride dashboard" only has to be made once.
    private static func presentActiveRide(_ activeRide: ActiveRideFeature.State, in state: inout State) {
        state.activeRide = activeRide
        state.isDashboardPresented = true
        state.selectedTab = .rides
    }

    /// Presents S05.1. Shared by the toolbar's Start Ride and S20's "Use This Route" (#195), so
    /// the two ways in cannot drift apart.
    ///
    /// Holds a pairing scan open for as long as the sheet is up, so its sensor rows report
    /// something the rider can act on. `startScanning` belongs to the active ride and ride finish
    /// disconnects, so without this every row would sit at its last known state — in practice
    /// disconnected — until the rider had already pressed Start. The scan is refcounted and
    /// independent of the ride's (BLE.md §8), the clients connect only what the rider has paired
    /// (#97), and a connection made here survives the scan ending, so the ride begins with its
    /// sensors already up.
    ///
    /// Here rather than inside the sheet, for the same reason the launch push lives here: the
    /// sheet is a `@Presents` child, and every dismissal path clears `startSheet` *before* SwiftUI
    /// runs `onDisappear` — so a release sent from the sheet arrives at an absent destination and
    /// TCA drops it, leaking a reference on all three clients per open. Only the owner of the
    /// presentation sees both ends of the lifetime.
    ///
    /// Sequential, and in the same order as the launch push, so the whole lifecycle is assertable
    /// as one interleaved call log.
    ///
    /// `route` is what S20's "Use This Route" chose; from here the sheet holds it (#196).
    private func presentStartSheet(_ state: inout State, route: RouteReference? = nil) -> Effect<Action> {
        // Nothing opens the sheet while a ride records. Every entry point hides itself then —
        // the toolbar's Start Ride, S20's button, S19's row swipe — but the rule lives here,
        // at the one place they all funnel through, because presenting the sheet mid-ride
        // would offer to start a second ride over the first.
        //
        // And a second tap before the sheet covers the button — or Use This Route with it already
        // up — must not replace the sheet, losing its route, or take a scan the one dismissal
        // cannot release.
        guard state.activeRide == nil, state.startSheet == nil else { return .none }
        state.startSheet = StartSheetFeature.State(route: route)
        return .run { [bleCSCClient, variaRadarClient, bleHRClient] _ in
            await bleCSCClient.beginPairingScan()
            await variaRadarClient.beginPairingScan()
            await bleHRClient.beginPairingScan()
        }
    }

    /// Balance the scan `presentStartSheet` took. Shared by the two paths the sheet
    /// can leave by, so neither can drift from the other.
    private static func endStartSheetScan(
        _ bleCSCClient: BLECSCClient,
        _ variaRadarClient: VariaRadarClient,
        _ bleHRClient: BLEHRClient
    ) -> Effect<Action> {
        .run { _ in
            await bleCSCClient.endPairingScan()
            await variaRadarClient.endPairingScan()
            await bleHRClient.endPairingScan()
        }
    }

    /// Thumbnails for rides that don't have one yet (#177): rides closed out here, which never
    /// reached `ActiveRideFeature`'s Finish, and any capture that failed. Tells the Rides tab
    /// when any landed, so rows already on screen go back for their image (#248).
    private static func backfillMapThumbnails(send: Send<Action>) async {
        if await RideMapThumbnail.backfill() > 0 {
            await send(.rides(.mapThumbnailsCaptured))
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
