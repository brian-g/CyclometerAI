import ComposableArchitecture
import Foundation
import Testing
@testable import Cyclometer

/// Matches the fixed clock the other `ActiveRideFeature` suites run on.
private let testDate = Date(timeIntervalSince1970: 1_000_000)

/// #262: auto-pause tested `speedMPS == 0`, which a GPS speed never is. These pin the
/// replacement — a stationary *band* (`stationarySpeedMPS`) with a higher bar to come
/// back out of it (`movingSpeedMPS`) — against the noise floor that defeated the old rule.
@MainActor
@Suite("ActiveRideFeature — auto-pause speed thresholds")
struct AutoPauseThresholdTests {

    /// A stationary iPhone's reported speed. Not invented: this is the raw magnitude the
    /// 2026-09-20 ride sat at for minutes while the rider stood still, which the GPX
    /// export's one-decimal rounding prints as `0.0`.
    private static let noiseFloorMPS = 0.04

    /// Quarantines `AppPreferences` in its own in-memory storage, for the same reason
    /// `ActiveRideFeatureTests` does: `isAutoPauseEnabled` is read off shared state, and
    /// without this it would resolve against whatever `app-preferences.json` exists on
    /// the machine running the suite. `state` is an autoclosure so it is built *inside*
    /// the dependency scope, after that storage is in place.
    private func makeStore(
        state: @autoclosure () -> ActiveRideFeature.State
    ) -> TestStoreOf<ActiveRideFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.isAutoPauseEnabled = true }
            let store = TestStore(initialState: state()) {
                ActiveRideFeature()
            } withDependencies: {
                $0.continuousClock = TestClock()
                $0.date = .constant(testDate)
                $0.uuid = .incrementing
                $0.hapticsClient = .testValue
                $0.audioClient = .testValue
                $0.variaRadarClient = .testValue
                $0.bleHRClient = .testValue
                $0.locationClient = .testValue
                $0.persistenceClient = .mock()
                $0.defaultFileStorage = storage
            }
            store.exhaustivity = .off
            return store
        }
    }

    @Test("GPS noise counts as stationary, so auto-pause reaches its threshold")
    func noiseFloorCountsTowardAutoPause() async {
        let store = makeStore(state: ActiveRideFeature.State(recordingState: .active))
        await store.send(.speed(.gpsSpeedReceived(Self.noiseFloorMPS)))

        for _ in 0..<ActiveRideFeature.autoPauseZeroSpeedSeconds {
            await store.send(.elapsedTick)
        }
        // The trigger is an effect action, so it lands on the send after the tick that
        // queued it — this one is what absorbs it.
        await store.send(.elapsedTick)

        #expect(store.state.recordingState == .paused)
        #expect(store.state.isAutoPaused)
    }

    @Test("A stationary rider's odometer does not grow")
    func noiseFloorAddsNoDistance() async {
        let store = makeStore(state: ActiveRideFeature.State(recordingState: .active))
        await store.send(.speed(.gpsSpeedReceived(Self.noiseFloorMPS)))

        for _ in 0..<5 {
            await store.send(.elapsedTick)
        }

        #expect(store.state.distanceMeters == 0)
        #expect(store.state.zeroSpeedSeconds == 5)
    }

    @Test("A speed above the stationary band resets the counter and advances the odometer")
    func movingSpeedResetsTheCounter() async {
        let store = makeStore(
            state: ActiveRideFeature.State(recordingState: .active, zeroSpeedSeconds: 5)
        )
        let speed = ActiveRideFeature.stationarySpeedMPS + 0.1
        await store.send(.speed(.gpsSpeedReceived(speed)))
        await store.send(.elapsedTick)

        #expect(store.state.zeroSpeedSeconds == 0)
        #expect(store.state.distanceMeters == speed)
    }

    @Test("Crawling out of the stationary band is not enough to auto-resume")
    func aCrawlDoesNotAutoResume() async {
        let store = makeStore(
            state: ActiveRideFeature.State(recordingState: .paused, isAutoPaused: true)
        )
        // Above `stationarySpeedMPS` but below `movingSpeedMPS` — the gap between the two
        // is what stops a single jittery sample undoing the pause a second after it lands.
        await store.send(.speed(.gpsSpeedReceived(ActiveRideFeature.movingSpeedMPS - 0.1)))

        #expect(store.state.recordingState == .paused)
        #expect(store.state.isAutoPaused)
    }

    @Test("Genuinely moving again auto-resumes")
    func movingAgainAutoResumes() async {
        let store = makeStore(
            state: ActiveRideFeature.State(
                recordingState: .paused,
                zeroSpeedSeconds: ActiveRideFeature.autoPauseZeroSpeedSeconds,
                isAutoPaused: true
            )
        )
        await store.send(.speed(.gpsSpeedReceived(ActiveRideFeature.movingSpeedMPS)))

        #expect(store.state.recordingState == .active)
        #expect(store.state.isAutoPaused == false)
        #expect(store.state.zeroSpeedSeconds == 0)
    }
}

/// Replays the six minutes of `Cyclometer_2026-09-20_10-45.gpx` that auto-pause slept
/// through, one second at a time, through the real reducer (#262).
///
/// `AutoPauseThresholdTests` pins each rule in isolation; this pins the outcome against
/// what the hardware actually produced — see `AutoPauseReplayFixtures` for what the GPX
/// export cost this data and why the replay asserts aggregates rather than exact seconds.
@MainActor
@Suite("ActiveRideFeature — 2026-09-20 stop replay")
struct AutoPauseReplayTests {

    private struct Replay {
        /// Seconds into the window at which the ride was paused, however briefly.
        var pausedSeconds: [Int] = []
        var distanceMeters: Double = 0
    }

    private func replay() async -> Replay {
        let storage = FileStorage.inMemory
        let store = withDependencies {
            $0.defaultFileStorage = storage
        } operation: { () -> TestStoreOf<ActiveRideFeature> in
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.isAutoPauseEnabled = true }
            let store = TestStore(initialState: ActiveRideFeature.State(recordingState: .active)) {
                ActiveRideFeature()
            } withDependencies: {
                $0.continuousClock = TestClock()
                $0.date = .constant(testDate)
                $0.uuid = .incrementing
                $0.hapticsClient = .testValue
                $0.audioClient = .testValue
                $0.variaRadarClient = .testValue
                $0.bleHRClient = .testValue
                $0.locationClient = .testValue
                $0.persistenceClient = .mock()
                $0.defaultFileStorage = storage
            }
            store.exhaustivity = .off
            return store
        }

        var result = Replay()
        for (second, speed) in AutoPauseReplayFixtures.stopWindowSpeedsMPS.enumerated() {
            await store.send(.speed(.gpsSpeedReceived(speed)))
            await store.send(.elapsedTick)
            if store.state.recordingState == .paused { result.pausedSeconds.append(second) }
        }
        result.distanceMeters = store.state.distanceMeters
        return result
    }

    @Test("The stop auto-pauses within half a minute of the rider stopping")
    func autoPausesPromptly() async {
        let replay = await self.replay()
        // The rider is still rolling at 3 m/s for the first nine seconds of the window and
        // the threshold is ten stationary seconds, so the earliest possible pause is t+19.
        #expect(replay.pausedSeconds.first != nil)
        #expect((replay.pausedSeconds.first ?? .max) <= 30)
    }

    @Test("The rider is paused for the great majority of the stop")
    func staysPausedThroughTheStop() async {
        let replay = await self.replay()
        // Two brief shuffles forward genuinely clear `movingSpeedMPS` and genuinely should
        // resume; everything else in these six minutes is a rider standing still.
        #expect(replay.pausedSeconds.count > 280)
        // And the window ends paused — 15:13:02Z is where the rider gave up and reached
        // for the Pause button, which the app should already have pressed for them.
        #expect(replay.pausedSeconds.last == AutoPauseReplayFixtures.stopWindowSpeedsMPS.count - 1)
    }

    @Test("A stop does not run the odometer")
    func theStopAddsLittleDistance() async {
        let replay = await self.replay()
        // The old rule integrated every noise sample and charged the ride 83 m for these
        // six minutes. What is left is the two real shuffles forward, nothing else.
        #expect(replay.distanceMeters < 50)
    }
}
