import Testing
import Foundation
import ComposableArchitecture
@testable import Cyclometer

/// Screen power management during a ride (#110): the wake lock and the idle
/// auto-dim. Both write process-global UIKit state, so everything here is asserted
/// through a recording `ScreenClient` rather than by observing the device.
@MainActor
@Suite("AppFeature — screen wake lock & auto-dim")
struct AppScreenPowerTests {

    enum ScreenCall: Equatable {
        case idleTimerDisabled(Bool)
        case setBrightness(Double)
    }

    /// A `ScreenClient` that records what it was asked to do and reports a fixed
    /// starting backlight level.
    static func recordingClient(
        brightness: Double,
        into calls: LockIsolated<[ScreenCall]>
    ) -> ScreenClient {
        ScreenClient(
            setIdleTimerDisabled: { disabled in
                calls.withValue { $0.append(.idleTimerDisabled(disabled)) }
            },
            brightness: { brightness },
            setBrightness: { level in
                calls.withValue { $0.append(.setBrightness(level)) }
            }
        )
    }

    /// Each store gets its own in-memory file system so the rider's real
    /// `app-preferences.json` is neither read nor written, and the Auto-dim seed
    /// cannot leak between tests. Seeding happens in the same scope as the store,
    /// otherwise the two would read different storage.
    static func makeStore(
        clock: TestClock<Duration>,
        calls: LockIsolated<[ScreenCall]>,
        brightness: Double = 0.8,
        isAutoDimEnabled: Bool = true
    ) -> TestStoreOf<AppFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.isAutoDimEnabled = isAutoDimEnabled }
            return TestStore(
                initialState: AppFeature.State(
                    activeRide: ActiveRideFeature.State(recordingState: .active),
                    isDashboardPresented: false
                )
            ) {
                AppFeature()
            } withDependencies: {
                $0.continuousClock = clock
                $0.screenClient = recordingClient(brightness: brightness, into: calls)
                $0.defaultFileStorage = storage
            }
        }
    }

    // MARK: - Wake lock

    /// The dashboard holds the wake lock; minimizing to the accessory pill gives it
    /// back. The pill case is the explicit carve-out in #110 — the rider isn't
    /// reading it, so the phone should auto-lock as usual even mid-ride.
    @Test("Dashboard disables the idle timer; minimizing to the pill re-enables it")
    func wakeLockFollowsDashboard() async {
        let clock = TestClock()
        let calls = LockIsolated<[ScreenCall]>([])
        let store = Self.makeStore(clock: clock, calls: calls)

        await store.send(.dashboardOpened) { $0.isDashboardPresented = true }
        await store.receive(\.screenVisibilityChanged)

        await store.send(.dashboardDismissed) { $0.isDashboardPresented = false }
        await store.receive(\.screenVisibilityChanged)
        await store.finish()

        // The ride is still running behind the pill — only the wake lock was released.
        #expect(store.state.activeRide != nil)
        #expect(calls.value == [.idleTimerDisabled(true), .idleTimerDisabled(false)])
    }

    /// A paused ride is not "actively being ridden" even though the dashboard stays
    /// on screen — the idle timer has to return to system default the moment the
    /// rider pauses, not only once the dashboard closes or the ride ends (#102).
    /// Exhaustivity off: the exact interleaving of `ActiveRideFeature`'s own
    /// suspension-forwarding effect against `AppFeature`'s visibility-forwarding
    /// effect isn't what this test is pinning.
    @Test("Pausing releases the idle timer even though the dashboard stays open")
    func pausingReleasesTheIdleTimer() async {
        let clock = TestClock()
        let calls = LockIsolated<[ScreenCall]>([])
        let store = Self.makeStore(clock: clock, calls: calls)
        store.exhaustivity = .off

        await store.send(.dashboardOpened) { $0.isDashboardPresented = true }
        #expect(calls.value == [.idleTimerDisabled(true)])

        await store.send(.activeRide(.pauseTapped))
        await store.finish()

        #expect(store.state.isDashboardPresented == true)
        #expect(store.state.activeRide?.recordingState == .paused)
        #expect(calls.value == [.idleTimerDisabled(true), .idleTimerDisabled(false)])
    }

    // MARK: - Auto-dim

    @Test("Dims after the idle timeout, capturing the rider's own brightness")
    func dimsAfterTimeout() async {
        let clock = TestClock()
        let calls = LockIsolated<[ScreenCall]>([])
        let store = Self.makeStore(clock: clock, calls: calls)

        await store.send(.dashboardOpened) { $0.isDashboardPresented = true }
        await store.receive(\.screenVisibilityChanged)

        await clock.advance(by: .seconds(AppFeature.dimAfterSeconds))
        await store.receive(\.dimTimerFired)
        await store.receive(\.preDimBrightnessCaptured) {
            $0.isDimmed = true
            $0.preDimBrightness = 0.8
        }

        await store.send(.dashboardDismissed) { $0.isDashboardPresented = false }
        await store.receive(\.screenVisibilityChanged) {
            $0.isDimmed = false
            $0.preDimBrightness = nil
        }
        await store.finish()

        #expect(calls.value.contains(.setBrightness(AppFeature.dimBrightness)))
        // Restores what the rider had, not an app-chosen constant.
        #expect(calls.value.contains(.setBrightness(0.8)))
    }

    /// A touch one second short of the timeout restarts the countdown rather than
    /// letting the original one fire — this is what `cancelInFlight` buys.
    @Test("Interaction restarts the countdown instead of racing it")
    func interactionRestartsCountdown() async {
        let clock = TestClock()
        let calls = LockIsolated<[ScreenCall]>([])
        let store = Self.makeStore(clock: clock, calls: calls)

        await store.send(.dashboardOpened) { $0.isDashboardPresented = true }
        await store.receive(\.screenVisibilityChanged)

        await clock.advance(by: .seconds(AppFeature.dimAfterSeconds - 1))
        await store.send(.userInteracted)

        // The original countdown's deadline passes with no dim.
        await clock.advance(by: .seconds(AppFeature.dimAfterSeconds - 1))
        #expect(store.state.isDimmed == false)

        // The restarted one fires on its own schedule.
        await clock.advance(by: .seconds(1))
        await store.receive(\.dimTimerFired)
        await store.receive(\.preDimBrightnessCaptured) {
            $0.isDimmed = true
            $0.preDimBrightness = 0.8
        }

        await store.send(.dashboardDismissed) { $0.isDashboardPresented = false }
        await store.receive(\.screenVisibilityChanged) {
            $0.isDimmed = false
            $0.preDimBrightness = nil
        }
        await store.finish()
    }

    /// The wake touch is the one that must not leave the rider's phone dark.
    @Test("A touch while dimmed wakes the screen and re-arms the countdown")
    func touchWakesTheScreen() async {
        let clock = TestClock()
        let calls = LockIsolated<[ScreenCall]>([])
        let store = Self.makeStore(clock: clock, calls: calls)

        await store.send(.dashboardOpened) { $0.isDashboardPresented = true }
        await store.receive(\.screenVisibilityChanged)
        await clock.advance(by: .seconds(AppFeature.dimAfterSeconds))
        await store.receive(\.dimTimerFired)
        await store.receive(\.preDimBrightnessCaptured) {
            $0.isDimmed = true
            $0.preDimBrightness = 0.8
        }

        await store.send(.userInteracted) {
            $0.isDimmed = false
            $0.preDimBrightness = nil
        }
        #expect(calls.value.last == .setBrightness(0.8))

        // Still on the dashboard, so it dims again on the next full interval.
        await clock.advance(by: .seconds(AppFeature.dimAfterSeconds))
        await store.receive(\.dimTimerFired)
        await store.receive(\.preDimBrightnessCaptured) {
            $0.isDimmed = true
            $0.preDimBrightness = 0.8
        }

        await store.send(.dashboardDismissed) { $0.isDashboardPresented = false }
        await store.receive(\.screenVisibilityChanged) {
            $0.isDimmed = false
            $0.preDimBrightness = nil
        }
        await store.finish()
    }

    /// Brightness is a system-wide setting, so backgrounding while dimmed has to give
    /// it back. This is what covers an app-switcher kill, which passes through
    /// `.background` on the way out.
    @Test("Backgrounding while dimmed restores brightness and the idle timer")
    func backgroundingRestoresEverything() async {
        let clock = TestClock()
        let calls = LockIsolated<[ScreenCall]>([])
        let store = Self.makeStore(clock: clock, calls: calls)

        await store.send(.dashboardOpened) { $0.isDashboardPresented = true }
        await store.receive(\.screenVisibilityChanged)
        await clock.advance(by: .seconds(AppFeature.dimAfterSeconds))
        await store.receive(\.dimTimerFired)
        await store.receive(\.preDimBrightnessCaptured) {
            $0.isDimmed = true
            $0.preDimBrightness = 0.8
        }

        await store.send(.scenePhaseChanged(isActive: false)) { $0.isForeground = false }
        await store.receive(\.screenVisibilityChanged) {
            $0.isDimmed = false
            $0.preDimBrightness = nil
        }
        await store.finish()

        // The dashboard is still "presented", but the app no longer owns the screen.
        #expect(store.state.isDashboardPresented == true)
        #expect(calls.value.contains(.setBrightness(0.8)))
        #expect(calls.value.contains(.idleTimerDisabled(false)))
    }

    /// The Settings toggle (S12) turns the dim off — and only the dim. A rider who
    /// doesn't want the screen going dark still needs it to stay *on*, so the wake
    /// lock is unaffected.
    @Test("Auto-dim off suppresses the dim but keeps the wake lock")
    func autoDimPreferenceOffSuppressesDim() async {
        let clock = TestClock()
        let calls = LockIsolated<[ScreenCall]>([])
        let store = Self.makeStore(clock: clock, calls: calls, isAutoDimEnabled: false)

        await store.send(.dashboardOpened) { $0.isDashboardPresented = true }
        await store.receive(\.screenVisibilityChanged)

        // Well past the timeout, with a touch in the middle for good measure.
        await clock.advance(by: .seconds(AppFeature.dimAfterSeconds * 2))
        await store.send(.userInteracted)
        await clock.advance(by: .seconds(AppFeature.dimAfterSeconds * 2))
        #expect(store.state.isDimmed == false)
        #expect(!calls.value.contains { if case .setBrightness = $0 { true } else { false } })

        // The wake lock was still taken, and is still released on the way out.
        await store.send(.dashboardDismissed) { $0.isDashboardPresented = false }
        await store.receive(\.screenVisibilityChanged)
        await store.finish()
        #expect(calls.value == [.idleTimerDisabled(true), .idleTimerDisabled(false)])
    }

    /// Dimming caps the backlight, it doesn't set it. A rider already riding at 5%
    /// in the dark must not be *brightened* to the dim level.
    @Test("Dim clamps rather than overrides a brightness already below the target")
    func dimNeverBrightens() async {
        let clock = TestClock()
        let calls = LockIsolated<[ScreenCall]>([])
        let store = Self.makeStore(clock: clock, calls: calls, brightness: 0.05)

        await store.send(.dashboardOpened) { $0.isDashboardPresented = true }
        await store.receive(\.screenVisibilityChanged)
        await clock.advance(by: .seconds(AppFeature.dimAfterSeconds))
        await store.receive(\.dimTimerFired)
        await store.receive(\.preDimBrightnessCaptured) {
            $0.isDimmed = true
            $0.preDimBrightness = 0.05
        }

        #expect(calls.value.contains(.setBrightness(0.05)))
        #expect(!calls.value.contains(.setBrightness(AppFeature.dimBrightness)))

        await store.send(.dashboardDismissed) { $0.isDashboardPresented = false }
        await store.receive(\.screenVisibilityChanged) {
            $0.isDimmed = false
            $0.preDimBrightness = nil
        }
        await store.finish()
    }
}
