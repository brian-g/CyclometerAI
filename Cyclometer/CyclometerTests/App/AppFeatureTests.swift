import Testing
import Foundation
import ComposableArchitecture
@testable import Cyclometer

@MainActor
@Suite("AppFeature — dashboard / accessory lifecycle")
struct AppFeatureTests {

    /// Minimizing the dashboard hides the cover but keeps the ride alive, so the
    /// accessory strip takes over (S05.3).
    @Test("dashboardDismissed hides cover but keeps the active ride")
    func dashboardDismissedKeepsRide() async {
        let store = TestStore(
            initialState: AppFeature.State(
                activeRide: ActiveRideFeature.State(recordingState: .active),
                isDashboardPresented: true
            )
        ) {
            AppFeature()
        }

        await store.send(.dashboardDismissed) {
            $0.isDashboardPresented = false
        }
        // Dropping to the accessory strip also hands the screen back to the system
        // (#110) — see AppScreenPowerTests for what that transition actually does.
        await store.receive(\.screenVisibilityChanged)
        #expect(store.state.activeRide != nil)
    }

    /// Tapping "Open" on the accessory re-presents the full-screen dashboard.
    @Test("dashboardOpened re-presents the dashboard while a ride is active")
    func dashboardOpenedRepresents() async {
        let store = TestStore(
            initialState: AppFeature.State(
                activeRide: ActiveRideFeature.State(recordingState: .active),
                isDashboardPresented: false
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.screenClient = .testValue
        }

        await store.send(.dashboardOpened) {
            $0.isDashboardPresented = true
        }
        // Presenting takes the screen (#110), which arms the auto-dim countdown;
        // minimizing again releases it so the countdown doesn't outlive the test.
        await store.receive(\.screenVisibilityChanged)
        await store.send(.dashboardDismissed) {
            $0.isDashboardPresented = false
        }
        await store.receive(\.screenVisibilityChanged)
    }

    /// With no active ride, `dashboardOpened` is a no-op (accessory can't be shown).
    @Test("dashboardOpened is a no-op with no active ride")
    func dashboardOpenedNoRide() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }

        await store.send(.dashboardOpened)
    }

    /// Regression: the ride's long-running effects (1 Hz timer, HR, radar,
    /// location) are started by AppFeature when the ride begins — bound to
    /// `activeRide` via `.ifLet` — NOT by a dashboard-view `.task`. This is what
    /// keeps the timer running when the dashboard is minimized to the accessory
    /// strip; previously the effects died with the dismissed dashboard view.
    @Test("Ride effects are started at the ride level, not by the dashboard view")
    func rideEffectsStartAtRideLevel() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()   // timer suspends; cancelled on finish
            $0.date = .constant(Date(timeIntervalSince1970: 1_000_000))
            $0.uuid = .incrementing
            $0.bleHRClient = .testValue
            $0.variaRadarClient = .testValue
            $0.locationClient = .testValue
            $0.hapticsClient = .testValue
        }
        store.exhaustivity = .off

        // Begin a ride via the start-sheet delegate. No dashboard cover / accessory
        // view is ever instantiated in this test — yet the ride still starts its
        // effects, because AppFeature emits `.task` itself.
        await store.send(.startRideButtonTapped)
        await store.send(.startSheet(.presented(.delegate(.startRide))))
        await store.receive(\.activeRide.task)
        #expect(store.state.activeRide?.recordingState == .active)

        // Finish via the real flow (pause → confirm) so the finish alert is
        // actually presented; this tears every ride effect down (activeRide → nil
        // via .ifLet) and lets the store settle cleanly.
        await store.send(.activeRide(.pauseTapped))
        await store.send(.activeRide(.finishTapped))
        await store.send(.activeRide(.finishAlert(.presented(.confirmFinish))))
        await store.finish()
        #expect(store.state.activeRide == nil)
    }

    /// #175: `.task` discovers a Ride a kill left behind and resumes it — the
    /// `AppFeature`-level wiring companion to `ActiveRideFeatureTests`'
    /// `State(resuming:)` tests and `RideRecordingTests.killAndRelaunchResumesRide`,
    /// neither of which exercises this reducer.
    @Test("task discovers a resumable ride and presents the dashboard")
    func taskDiscoversResumableRide() async {
        let summary = RideSummaryUpdate(
            rideId: UUID(), recordingState: .active,
            durationSeconds: 120, distanceMeters: 800, averageSpeedMPS: 5, maxSpeedMPS: 9
        )
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.date = .constant(Date(timeIntervalSince1970: 1_000_000))
            $0.uuid = .incrementing
            $0.bleCSCClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.screenClient = .testValue
            $0.hapticsClient = .testValue
            $0.locationClient = .testValue
            $0.persistenceClient = .mock(resumableRide: summary)
        }
        store.exhaustivity = .off

        await store.send(.task)
        await store.receive(\.resumableRideFetched)
        #expect(store.state.activeRide?.rideId == summary.rideId)
        #expect(store.state.activeRide?.recordingState == .active)
        #expect(store.state.isDashboardPresented == true)
        #expect(store.state.selectedTab == .rides)
        await store.receive(\.activeRide.task)
    }
}
