import ComposableArchitecture
import Foundation
import Testing
@testable import Cyclometer

/// #308 — the ride's Live Activity: started with the ride, fed from its 1 Hz tick, kept alive
/// while nothing changes, ended with the ride, and retried when the app comes forward.
///
/// Every store runs the whole `ActiveRideFeature`, which `LiveActivityFeature` is layered onto,
/// with a recording `LiveActivityClient`. Assertions are on the client's calls: what reached
/// ActivityKit is the contract.
@MainActor
@Suite("LiveActivityFeature")
struct LiveActivityFeatureTests {
    typealias Content = RideActivityAttributes.ContentState

    enum Call: Equatable {
        case start(RideActivityAttributes, Content)
        case update(Content)
        case end
    }

    nonisolated static let t0 = Date(timeIntervalSince1970: 1_000_000)

    /// `starts` answers each `start` in turn; past its end, true.
    static func recordingClient(
        into calls: LockIsolated<[Call]>,
        isEnabled: Bool = true,
        starts: [Bool] = []
    ) -> LiveActivityClient {
        let answers = LockIsolated(starts)
        return LiveActivityClient(
            start: { attributes, content in
                calls.withValue { $0.append(.start(attributes, content)) }
                return answers.withValue { $0.isEmpty ? true : $0.removeFirst() }
            },
            update: { content in calls.withValue { $0.append(.update(content)) } },
            end: { calls.withValue { $0.append(.end) } },
            isEnabled: { isEnabled }
        )
    }

    /// A ride whose date moves with the clock that drives its tick.
    @MainActor
    struct Ride {
        let store: TestStoreOf<ActiveRideFeature>
        let clock: TestClock<Duration>
        let now: LockIsolated<Date>
        let calls: LockIsolated<[Call]>

        /// `n` seconds of the ride's 1 Hz timer, the date moving alongside.
        func tick(_ n: Int = 1) async {
            for _ in 0..<n {
                now.withValue { $0.addTimeInterval(1) }
                await clock.advance(by: .seconds(1))
            }
        }

        /// Starts the ride, and waits for ActivityKit's answer.
        func start() async {
            await store.send(.task)
            await store.receive(\.liveActivity.started)
        }
    }

    /// The state is built inside the store's own in-memory preferences, so its `@Shared` reads
    /// them and not the machine's (`ActiveRideFeatureTests`' pattern). Auto-pause is off: the
    /// rides here stand still on purpose.
    static func makeRide(
        isEnabled: Bool = true,
        configure: (inout ActiveRideFeature.State) -> Void = { _ in }
    ) -> Ride {
        let storage = FileStorage.inMemory
        let clock = TestClock()
        let now = LockIsolated(t0)
        let calls = LockIsolated<[Call]>([])
        let store = withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock {
                $0.preferredUnit = .imperial
                $0.isAutoPauseEnabled = false
                $0.isTurnByTurnEnabled = true
            }
            var state = ActiveRideFeature.State(recordingState: .idle)
            configure(&state)
            return TestStore(initialState: state) {
                ActiveRideFeature()
            } withDependencies: {
                $0.continuousClock = clock
                $0.date = DateGenerator { now.value }
                $0.defaultFileStorage = storage
                $0.liveActivityClient = recordingClient(into: calls, isEnabled: isEnabled)
            }
        }
        store.exhaustivity = .off
        return Ride(store: store, clock: clock, now: now, calls: calls)
    }

    // MARK: - Start

    @Test("the ride's start shows it, riding, in the rider's units")
    func startShowsTheRide() async {
        let ride = Self.makeRide()
        let calls = ride.calls
        await ride.start()

        #expect(calls.value == [.start(
            RideActivityAttributes(units: .imperial),
            Content(status: .riding, startDate: Self.t0, pausedElapsed: nil,
                    speedMPS: 0, distanceMeters: 0, routeProgress: nil)
        )])
        #expect(ride.store.state.liveActivity.phase == .showing)
    }

    @Test("with Live Activities off, nothing reaches ActivityKit")
    func disabledShowsNothing() async {
        let ride = Self.makeRide(isEnabled: false)
        let calls = ride.calls
        await ride.store.send(.task)
        await ride.tick(20)

        #expect(calls.value.isEmpty)
        #expect(ride.store.state.liveActivity.phase == .notShowing)
    }

    @Test("with S12's Show Live Activity off, nothing reaches ActivityKit, even on coming forward")
    func settingOffShowsNothing() async {
        let ride = Self.makeRide { $0.$preferences.withLock { $0.isLiveActivityEnabled = false } }
        let calls = ride.calls
        await ride.store.send(.task)
        await ride.store.send(.liveActivity(.appBecameActive))
        await ride.tick(20)

        #expect(calls.value.isEmpty)
        #expect(ride.store.state.liveActivity.phase == .notShowing)
    }

    /// A ride resumed after a crash comes back as it was left; paused, its card shows paused.
    @Test("a resumed, paused ride starts paused, at its elapsed time")
    func resumedPausedRideStartsPaused() async {
        let ride = Self.makeRide {
            $0.recordingState = .paused
            $0.elapsedSeconds = 600
            $0.distanceMeters = 5_000
        }
        await ride.start()

        #expect(ride.calls.value == [.start(
            RideActivityAttributes(units: .imperial),
            Content(status: .paused, startDate: Self.t0.addingTimeInterval(-600), pausedElapsed: 600,
                    speedMPS: 0, distanceMeters: 5_000, routeProgress: nil)
        )])
    }

    @Test("route progress is navigation's, as the mini-player's ring shows it")
    func routeProgressIsNavigations() async throws {
        let legs: [RouteFixtures.Leg] = [(0, 3_000)]
        let route = try #require(NavigationRoute(coordinates: RouteFixtures.path(legs: legs), maneuvers: []))
        let ride = Self.makeRide {
            $0.navigation.activeRoute = route
            $0.navigation.progressMeters = route.totalDistanceMeters / 2
        }
        await ride.start()

        guard case .start(_, let content) = try #require(ride.calls.value.first) else {
            Issue.record("no start"); return
        }
        let progress = try #require(content.routeProgress)
        #expect(abs(progress - 0.5) < 1e-9)
    }

    // MARK: - Updates

    /// Readings arrive faster than once a second; the tick is the throttle.
    @Test("readings between two ticks reach the activity as one update, at the tick")
    func readingsCoalesceToTheTick() async {
        let ride = Self.makeRide()
        let calls = ride.calls
        await ride.start()
        await ride.tick()
        #expect(calls.updates.isEmpty, "the first second changed nothing")

        for speed in [3.0, 4, 5] {
            await ride.store.send(.speed(.gpsSpeedReceived(speed)))
        }
        #expect(calls.updates.isEmpty, "nothing ahead of the tick")

        await ride.tick()
        await expectEventually("one update, at the tick") { calls.updates.count == 1 }
        #expect(calls.updates.last?.speedMPS == 5)
        #expect(calls.updates.last?.distanceMeters == 5)
        #expect(calls.updates.last?.startDate == Self.t0)
    }

    /// The stale date is 30 s after each update; without these an idle ride's card would dim.
    @Test("an unchanged ride is sent again every 15 ticks, not before")
    func unchangedRideIsKeptAlive() async {
        let ride = Self.makeRide()
        let calls = ride.calls
        await ride.start()

        await ride.tick(LiveActivityFeature.keepAliveTicks - 1)
        #expect(calls.updates.isEmpty)
        await ride.tick()
        await expectEventually("a keep-alive") { calls.updates.count == 1 }
        #expect(calls.updates.last == Content(status: .riding, startDate: Self.t0, pausedElapsed: nil,
                                             speedMPS: 0, distanceMeters: 0, routeProgress: nil))

        await ride.tick(LiveActivityFeature.keepAliveTicks)
        await expectEventually("the next, 15 ticks on") { calls.updates.count == 2 }
    }

    @Test("a pause shows at the next tick, frozen at the elapsed time, and stays alive")
    func pauseShowsAndStaysAlive() async {
        let ride = Self.makeRide()
        let calls = ride.calls
        await ride.start()
        await ride.tick(10)
        await ride.store.send(.pauseTapped)
        #expect(calls.updates.isEmpty)

        await ride.tick()
        await expectEventually("the pause") { calls.updates.count == 1 }
        let paused = Content(status: .paused, startDate: Self.t0, pausedElapsed: 10,
                             speedMPS: 0, distanceMeters: 0, routeProgress: nil)
        #expect(calls.updates.last == paused)

        await ride.tick(LiveActivityFeature.keepAliveTicks)
        await expectEventually("a keep-alive while paused") { calls.updates.count == 2 }
        #expect(calls.updates.last == paused)
    }

    @Test("a resume after a minute's pause moves the timer's start on by the minute")
    func resumeMovesTheStart() async {
        let ride = Self.makeRide()
        let calls = ride.calls
        await ride.start()
        await ride.tick(10)
        await ride.store.send(.pauseTapped)
        await ride.tick(60)
        await expectEventually { calls.updates.count == 4 }  // the pause + 3 keep-alives

        await ride.store.send(.resumeTapped)
        await ride.tick()
        await expectEventually("the resume") { calls.updates.count == 5 }
        #expect(calls.updates.last == Content(status: .riding, startDate: Self.t0.addingTimeInterval(60),
                                             pausedElapsed: nil, speedMPS: 0, distanceMeters: 0,
                                             routeProgress: nil))
    }

    /// A one-tick pause moves the start by exactly the second the anchor's tolerance allows; kept,
    /// the Lock Screen's timer would read a second over the dashboard's for the rest of the ride.
    @Test("a resume after a one-second pause still moves the timer's start")
    func resumeAfterOneSecondMovesTheStart() async {
        let ride = Self.makeRide()
        let calls = ride.calls
        await ride.start()
        await ride.tick(10)
        await ride.store.send(.pauseTapped)
        await ride.tick()
        await expectEventually("the pause") { calls.updates.count == 1 }

        await ride.store.send(.resumeTapped)
        await ride.tick()
        await expectEventually("the resume") { calls.updates.count == 2 }
        #expect(calls.updates.last?.startDate == Self.t0.addingTimeInterval(1))
    }

    // MARK: - The timer's start

    @Test("the start shown is kept within a second of the elapsed time, and replaced beyond it")
    func startDateAnchor() {
        withDependencies {
            $0.defaultFileStorage = .inMemory
        } operation: {
            var state = ActiveRideFeature.State(recordingState: .active)
            state.elapsedSeconds = 100
            state.liveActivity.shown = Content(status: .riding, startDate: Self.t0, pausedElapsed: nil,
                                               speedMPS: 0, distanceMeters: 0, routeProgress: nil)
            let start = { (now: TimeInterval) in
                LiveActivityFeature.content(for: state, now: Self.t0.addingTimeInterval(now)).startDate
            }
            #expect(start(100.9) == Self.t0)
            #expect(start(99.1) == Self.t0)
            #expect(start(102) == Self.t0.addingTimeInterval(2))

            state.recordingState = .paused
            #expect(start(500) == Self.t0, "a pause keeps the start it had")
        }
    }

    // MARK: - Through AppFeature

    /// `AppFeature` nils the ride on this very action, so the end can't be a forwarded action.
    @Test("finishing the ride ends the activity, and nothing follows")
    func finishEndsTheActivity() async {
        let calls = LockIsolated<[Call]>([])
        let clock = TestClock()
        let store = Self.makeAppStore(clock: clock, calls: calls)

        await store.send(.activeRide(.task))
        await store.receive(\.activeRide.liveActivity.started)
        await store.send(.activeRide(.pauseTapped))
        await store.send(.activeRide(.finishTapped))
        await store.send(.activeRide(.finishAlert(.presented(.confirmFinish))))
        #expect(store.state.activeRide == nil)
        await expectEventually("the activity ended") { calls.value.last == .end }

        await clock.advance(by: .seconds(60))
        #expect(calls.value.filter { $0 == .end }.count == 1)
        #expect(calls.value.last == .end, "no update after the end")
    }

    /// ActivityKit refuses a request from the background, as when a ride resumes there.
    @Test("a refused start is tried again when the app comes forward; a showing one isn't")
    func refusedStartRetriesInTheForeground() async {
        let calls = LockIsolated<[Call]>([])
        let store = Self.makeAppStore(clock: TestClock(), calls: calls, starts: [false])
        let starts = { calls.value.filter { if case .start = $0 { true } else { false } }.count }

        await store.send(.activeRide(.task))
        await store.receive(\.activeRide.liveActivity.started)
        #expect(store.state.activeRide?.liveActivity.phase == .notShowing)

        await store.send(.scenePhaseChanged(isActive: false))
        #expect(starts() == 1, "not in the background")

        await store.send(.scenePhaseChanged(isActive: true))
        await store.receive(\.activeRide.liveActivity.started)
        #expect(starts() == 2)
        #expect(store.state.activeRide?.liveActivity.phase == .showing)

        await store.send(.scenePhaseChanged(isActive: false))
        await store.send(.scenePhaseChanged(isActive: true))
        #expect(starts() == 2, "a showing activity isn't started again")
    }

    // MARK: - S12 setting (#313)

    @Test("turned off mid-ride, the activity ends, and coming forward doesn't bring it back")
    func settingOffMidRideEnds() async {
        let ride = Self.makeRide()
        let calls = ride.calls
        await ride.start()

        ride.store.state.$preferences.withLock { $0.isLiveActivityEnabled = false }
        await ride.store.send(.liveActivity(.preferenceChanged))
        #expect(ride.store.state.liveActivity.phase == .notShowing)
        await expectEventually("the activity ended") { calls.value.last == .end }

        await ride.store.send(.liveActivity(.appBecameActive))
        await ride.tick(20)
        #expect(calls.value.last == .end, "nothing after the end")
    }

    @Test("turned on mid-ride, the activity starts")
    func settingOnMidRideStarts() async {
        let ride = Self.makeRide { $0.$preferences.withLock { $0.isLiveActivityEnabled = false } }
        let calls = ride.calls
        await ride.store.send(.task)
        await ride.tick(3)
        #expect(calls.value.isEmpty)

        ride.store.state.$preferences.withLock { $0.isLiveActivityEnabled = true }
        await ride.store.send(.liveActivity(.preferenceChanged))
        await ride.store.receive(\.liveActivity.started)

        #expect(calls.value.count == 1)
        guard case .start(_, let content) = calls.value.first else {
            Issue.record("expected a start, got \(calls.value)")
            return
        }
        #expect(content.pausedElapsed == nil)
        #expect(ride.store.state.liveActivity.phase == .showing)
    }

    /// `Activity.request` can land after the `end` the setting sent, which found nothing to end.
    @Test("turned off while the start is pending, the activity it then shows is ended")
    func settingOffWhileStartingEndsTheLateActivity() async {
        let ride = Self.makeRide()
        let calls = ride.calls
        let clock = ride.clock
        var client = Self.recordingClient(into: calls)
        let recordedStart = client.start
        client.start = { attributes, content in
            try? await clock.sleep(for: .milliseconds(500))
            return await recordedStart(attributes, content)
        }
        ride.store.dependencies.liveActivityClient = client

        await ride.store.send(.task)
        #expect(ride.store.state.liveActivity.phase == .starting)
        ride.store.state.$preferences.withLock { $0.isLiveActivityEnabled = false }
        await ride.store.send(.liveActivity(.preferenceChanged))
        await clock.advance(by: .milliseconds(500))
        await ride.store.receive(\.liveActivity.started)

        await expectEventually("the late activity ended") {
            calls.value.last == .end && calls.value.filter { $0 == .end }.count == 2
        }
        #expect(ride.store.state.liveActivity.phase == .notShowing)
    }

    @Test("turning it off in Settings during a ride reaches the ride's activity")
    func settingsToggleReachesTheRide() async {
        let calls = LockIsolated<[Call]>([])
        let store = Self.makeAppStore(clock: TestClock(), calls: calls)

        await store.send(.activeRide(.task))
        await store.receive(\.activeRide.liveActivity.started)
        await store.send(.settings(.liveActivityToggled))
        await store.receive(\.settings.delegate.liveActivityToggled)
        await store.receive(\.activeRide.liveActivity.preferenceChanged)

        #expect(store.state.activeRide?.liveActivity.phase == .notShowing)
        await expectEventually("the activity ended") { calls.value.last == .end }
    }

    static func makeAppStore(
        clock: TestClock<Duration>,
        calls: LockIsolated<[Call]>,
        starts: [Bool] = []
    ) -> TestStoreOf<AppFeature> {
        let storage = FileStorage.inMemory
        let store = withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.isAutoPauseEnabled = false }
            return TestStore(
                initialState: AppFeature.State(activeRide: ActiveRideFeature.State(recordingState: .idle))
            ) {
                AppFeature()
            } withDependencies: {
                $0.continuousClock = clock
                $0.date = .constant(t0)
                $0.calendar = Calendar(identifier: .gregorian)  // the finish names the ride
                $0.defaultFileStorage = storage
                $0.liveActivityClient = recordingClient(into: calls, starts: starts)
            }
        }
        store.exhaustivity = .off
        return store
    }
}

private extension LockIsolated where Value == [LiveActivityFeatureTests.Call] {
    nonisolated var updates: [LiveActivityFeatureTests.Content] {
        value.compactMap { if case .update(let content) = $0 { content } else { nil } }
    }
}
