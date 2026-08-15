import Testing
import ComposableArchitecture
import CoreLocation
@testable import Cyclometer

/// Fixed clock for SpeedFeature's timestamped samples in TestStores.
private let testDate = Date(timeIntervalSince1970: 1_000_000)

@MainActor
@Suite("ActiveRideFeature — radar wiring")
struct ActiveRideFeatureRadarTests {

    private func makeStore(
        clock: TestClock<Duration>,
        advisoryCount: LockIsolated<Int>
    ) -> TestStoreOf<ActiveRideFeature> {
        var haptics = HapticsClient.testValue
        haptics.playAdvisory = { advisoryCount.withValue { $0 += 1 } }
        return TestStore(initialState: ActiveRideFeature.State()) {
            ActiveRideFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.hapticsClient = haptics
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.locationClient = .testValue
        }
    }

    @Test("Radar targets update state")
    func targetsUpdateState() async {
        let store = makeStore(clock: TestClock(), advisoryCount: LockIsolated(0))
        let targets = [
            RadarTarget(
                id: VariaRadarClient.vehicleSlotIDs[0],
                relativeVelocityMPS: 8,
                rangeMetres: 40,
                threatLevel: .danger
            )
        ]
        await store.send(.radarTargetsUpdated(targets)) {
            $0.radarTargets = targets
        }
    }

    @Test("Active connection sets paired badge")
    func activeSetsPaired() async {
        let store = makeStore(clock: TestClock(), advisoryCount: LockIsolated(0))
        await store.send(.radarConnectionChanged(.active)) {
            $0.isRadarPaired = true
        }
    }

    @Test("Disconnect during ride: badge flips and L1 advisory haptic fires once after 10s")
    func disconnectBadgeAndHaptic() async {
        let clock = TestClock()
        let advisoryCount = LockIsolated(0)
        let store = makeStore(clock: clock, advisoryCount: advisoryCount)

        await store.send(.radarConnectionChanged(.active)) {
            $0.isRadarPaired = true
        }
        await store.send(.radarTargetsUpdated([
            RadarTarget(
                id: VariaRadarClient.vehicleSlotIDs[0],
                relativeVelocityMPS: 5,
                rangeMetres: 60,
                threatLevel: .warning
            )
        ])) {
            $0.radarTargets = [
                RadarTarget(
                    id: VariaRadarClient.vehicleSlotIDs[0],
                    relativeVelocityMPS: 5,
                    rangeMetres: 60,
                    threatLevel: .warning
                )
            ]
        }

        // Badge stays paired during the 10s grace window.
        await store.send(.radarConnectionChanged(.reconnecting))
        await clock.advance(by: .seconds(10))
        await store.receive(\.radarReconnectTimedOut) {
            $0.isRadarPaired = false
            $0.radarTargets = []
        }
        #expect(advisoryCount.value == 1)

        // A second .reconnecting while unpaired does not re-arm the timer.
        await store.send(.radarConnectionChanged(.reconnecting))
        await clock.advance(by: .seconds(60))
        #expect(advisoryCount.value == 1)
    }

    @Test("Reconnection within 10s cancels the timer — no badge flip, no haptic")
    func recoveryWithinGraceWindow() async {
        let clock = TestClock()
        let advisoryCount = LockIsolated(0)
        let store = makeStore(clock: clock, advisoryCount: advisoryCount)

        await store.send(.radarConnectionChanged(.active)) {
            $0.isRadarPaired = true
        }
        await store.send(.radarConnectionChanged(.reconnecting))
        await clock.advance(by: .seconds(9))
        await store.send(.radarConnectionChanged(.active))
        await clock.advance(by: .seconds(60))
        #expect(advisoryCount.value == 0)
    }

    @Test("Terminal disconnect clears badge and targets immediately")
    func terminalDisconnect() async {
        let store = makeStore(clock: TestClock(), advisoryCount: LockIsolated(0))
        await store.send(.radarConnectionChanged(.active)) {
            $0.isRadarPaired = true
        }
        await store.send(.radarConnectionChanged(.disconnected)) {
            $0.isRadarPaired = false
            $0.radarTargets = []
        }
    }
}

// MARK: - Location wiring

@MainActor
@Suite("ActiveRideFeature — location wiring")
struct ActiveRideFeatureLocationTests {

    private static let sampleUpdate = LocationUpdate(
        coordinate: Coordinate(latitude: 43.0731, longitude: -89.4012),
        altitude: 280.0,
        speed: 8.5,
        horizontalAccuracy: 5.0,
        heading: 192.0,
        timestamp: Date(timeIntervalSince1970: 1_000_000)
    )

    private func makeStore(
        recordingState: RideRecordingState = .active
    ) -> TestStoreOf<ActiveRideFeature> {
        TestStore(initialState: ActiveRideFeature.State(recordingState: recordingState)) {
            ActiveRideFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.date = .constant(testDate)
            $0.hapticsClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.locationClient = .testValue
        }
    }

    @Test("Location update populates state")
    func locationUpdatePopulatesState() async {
        let store = makeStore()
        await store.send(.locationUpdated(Self.sampleUpdate)) {
            $0.coordinate = Coordinate(latitude: 43.0731, longitude: -89.4012)
            $0.trackCoordinates = [Coordinate(latitude: 43.0731, longitude: -89.4012)]
            $0.altitude = 280.0
            $0.horizontalAccuracy = 5.0
            $0.heading = 192.0
            $0.speedKPH = 8.5 * 3.6
            $0.speedSampleCount = 1
            $0.speedSampleSum = 8.5 * 3.6
            $0.maxSpeedKPH = 8.5 * 3.6
        }
        await store.receive(.speed(.gpsSpeedReceived(8.5))) {
            $0.speed.speedMPS = 8.5
            $0.speed.activeSpeedSource = .gps
            $0.speed.latestGPSSpeedMPS = 8.5
            $0.speed.speedSamples = [SpeedSample(time: testDate, mps: 8.5)]
        }
        // Calibration tracks fix quality independently of whether it is accumulating.
        await store.receive(\.calibration.locationUpdated) {
            $0.calibration.isGPSUsable = true
            $0.calibration.lastFixTimestamp = Self.sampleUpdate.timestamp
        }
    }

    @Test("Location updates continue while paused")
    func locationContinuesWhilePaused() async {
        let store = makeStore()
        await store.send(.locationUpdated(Self.sampleUpdate)) {
            $0.coordinate = Coordinate(latitude: 43.0731, longitude: -89.4012)
            $0.trackCoordinates = [Coordinate(latitude: 43.0731, longitude: -89.4012)]
            $0.altitude = 280.0
            $0.horizontalAccuracy = 5.0
            $0.heading = 192.0
            $0.speedKPH = 8.5 * 3.6
            $0.speedSampleCount = 1
            $0.speedSampleSum = 8.5 * 3.6
            $0.maxSpeedKPH = 8.5 * 3.6
        }
        await store.receive(.speed(.gpsSpeedReceived(8.5))) {
            $0.speed.speedMPS = 8.5
            $0.speed.activeSpeedSource = .gps
            $0.speed.latestGPSSpeedMPS = 8.5
            $0.speed.speedSamples = [SpeedSample(time: testDate, mps: 8.5)]
        }
        await store.receive(\.calibration.locationUpdated) {
            $0.calibration.isGPSUsable = true
            $0.calibration.lastFixTimestamp = Self.sampleUpdate.timestamp
        }
        await store.send(.pauseTapped) {
            $0.recordingState = .paused
        }
        await store.receive(\.calibration.suspensionChanged) {
            $0.calibration.isSuspended = true
        }

        let pausedUpdate = LocationUpdate(
            coordinate: Coordinate(latitude: 44.0, longitude: -90.0),
            altitude: 300.0,
            speed: 12.0,
            horizontalAccuracy: 3.0,
            heading: 45.0,
            timestamp: Date(timeIntervalSince1970: 1_000_001)
        )
        await store.send(.locationUpdated(pausedUpdate)) {
            $0.coordinate = Coordinate(latitude: 44.0, longitude: -90.0)
            // trackCoordinates does NOT grow while paused — it stays at the single
            // point recorded during the active update above.
            $0.altitude = 300.0
            $0.horizontalAccuracy = 3.0
            $0.heading = 45.0
            $0.speedKPH = 12.0 * 3.6
            $0.speedSampleCount = 2
            $0.speedSampleSum = 8.5 * 3.6 + 12.0 * 3.6
            $0.maxSpeedKPH = 12.0 * 3.6
        }
        await store.receive(.speed(.gpsSpeedReceived(12.0))) {
            $0.speed.speedMPS = 12.0
            $0.speed.activeSpeedSource = .gps
            $0.speed.latestGPSSpeedMPS = 12.0
            $0.speed.speedSamples = [
                SpeedSample(time: testDate, mps: 8.5),
                SpeedSample(time: testDate, mps: 12.0)
            ]
        }
        await store.receive(\.calibration.locationUpdated) {
            $0.calibration.lastFixTimestamp = pausedUpdate.timestamp
        }
    }

    @Test("Invalid location speed clears SpeedFeature state")
    func invalidLocationSpeedClearsSpeedFeature() async {
        let store = makeStore()
        await store.send(.speed(.gpsSpeedReceived(8.5))) {
            $0.speed.speedMPS = 8.5
            $0.speed.activeSpeedSource = .gps
            $0.speed.latestGPSSpeedMPS = 8.5
            $0.speed.speedSamples = [SpeedSample(time: testDate, mps: 8.5)]
        }

        let invalidUpdate = LocationUpdate(
            coordinate: Coordinate(latitude: 43.0731, longitude: -89.4012),
            altitude: 280.0,
            speed: -1,
            horizontalAccuracy: 5.0,
            heading: 192.0,
            timestamp: Date(timeIntervalSince1970: 1_000_002)
        )

        await store.send(.locationUpdated(invalidUpdate)) {
            $0.coordinate = Coordinate(latitude: 43.0731, longitude: -89.4012)
            $0.trackCoordinates = [Coordinate(latitude: 43.0731, longitude: -89.4012)]
            $0.altitude = 280.0
            $0.horizontalAccuracy = 5.0
            $0.heading = 192.0
            $0.speedKPH = 0
        }
        await store.receive(.speed(.gpsSpeedReceived(-1))) {
            $0.speed.speedMPS = nil
            $0.speed.activeSpeedSource = .none
            $0.speed.latestGPSSpeedMPS = nil
        }
        // An invalid-speed fix is rejected outright, so nothing about the window moves.
        await store.receive(\.calibration.locationUpdated)
    }

    @Test("Authorization denied sets isLocationAvailable false")
    func authDenied() async {
        let store = makeStore()
        await store.send(.locationAuthorizationResult(.denied))
    }

    @Test("Authorization granted sets isLocationAvailable true")
    func authGranted() async {
        let store = makeStore()
        await store.send(.locationAuthorizationResult(.authorizedWhenInUse)) {
            $0.isLocationAvailable = true
        }
    }

    @Test("Authorization authorizedAlways also sets isLocationAvailable true")
    func authAlways() async {
        let store = makeStore()
        await store.send(.locationAuthorizationResult(.authorizedAlways)) {
            $0.isLocationAvailable = true
        }
    }

    @Test("Finish ride calls stopUpdates")
    func finishCallsStop() async {
        let stopCalled = LockIsolated(false)
        let store = TestStore(
            initialState: ActiveRideFeature.State(recordingState: .active)
        ) {
            ActiveRideFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.hapticsClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.locationClient = LocationClient(
                requestAuthorization: { .authorizedWhenInUse },
                startUpdates: { AsyncStream { $0.finish() } },
                stopUpdates: { stopCalled.setValue(true) }
            )
        }
        await store.send(.pauseTapped) {
            $0.recordingState = .paused
        }
        await store.receive(\.calibration.suspensionChanged) {
            $0.calibration.isSuspended = true
        }
        await store.send(.finishTapped) {
            $0.finishAlert = AlertState {
                TextState("Finish Ride")
            } actions: {
                ButtonState(role: .destructive, action: .confirmFinish) {
                    TextState("Finish")
                }
                ButtonState(role: .cancel) {
                    TextState("Cancel")
                }
            }
        }
        await store.send(.finishAlert(.presented(.confirmFinish))) {
            $0.recordingState = .ended
            $0.finishAlert = nil
        }
        #expect(stopCalled.value == true)
    }
}

// MARK: - 1 Hz timer

@MainActor
@Suite("ActiveRideFeature — 1 Hz timer")
struct ActiveRideFeatureTimerTests {

    private func makeStore(
        speedMPS: Double = 0
    ) -> TestStoreOf<ActiveRideFeature> {
        TestStore(
            initialState: ActiveRideFeature.State(
                recordingState: .active,
                speed: SpeedFeature.State(
                    speedMPS: speedMPS >= 0 ? speedMPS : nil,
                    activeSpeedSource: speedMPS >= 0 ? .gps : .none
                )
            )
        ) {
            ActiveRideFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.hapticsClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.locationClient = .testValue
        }
    }

    @Test("5 ticks increment elapsedSeconds to 5")
    func fiveTicksElapsed() async {
        let store = makeStore()
        for tick in 1...5 {
            await store.send(.elapsedTick) {
                $0.elapsedSeconds = tick
                $0.zeroSpeedSeconds = tick
            }
        }
    }

    @Test("Paused tick does not increment elapsedSeconds")
    func pausedTickNoElapsed() async {
        let store = makeStore()
        await store.send(.pauseTapped) {
            $0.recordingState = .paused
        }
        await store.receive(\.calibration.suspensionChanged) {
            $0.calibration.isSuspended = true
        }
        await store.send(.elapsedTick)
    }

    @Test("Distance accumulates from speedMPS per tick")
    func distanceAccumulates() async {
        let store = makeStore(speedMPS: 10.0)
        await store.send(.elapsedTick) {
            $0.elapsedSeconds = 1
            $0.distanceMeters = 10.0
        }
        await store.send(.elapsedTick) {
            $0.elapsedSeconds = 2
            $0.distanceMeters = 20.0
        }
    }

    @Test("Distance does not accumulate while paused")
    func distanceDoesNotAccumulateWhilePaused() async {
        let store = makeStore(speedMPS: 10.0)
        await store.send(.pauseTapped) {
            $0.recordingState = .paused
        }
        await store.receive(\.calibration.suspensionChanged) {
            $0.calibration.isSuspended = true
        }
        await store.send(.elapsedTick)
        await store.send(.elapsedTick)
    }

    @Test("Negative speedMPS does not accumulate distance")
    func negativeSpeedIgnored() async {
        let store = makeStore(speedMPS: -1)
        await store.send(.elapsedTick) {
            $0.elapsedSeconds = 1
            $0.zeroSpeedSeconds = 1
        }
    }

    @Test("Resume after pause: elapsed and distance resume, no phantom distance during pause")
    func resumeAfterPause() async {
        let store = makeStore(speedMPS: 10.0)
        await store.send(.elapsedTick) {
            $0.elapsedSeconds = 1
            $0.distanceMeters = 10.0
        }
        await store.send(.pauseTapped) {
            $0.recordingState = .paused
        }
        await store.receive(\.calibration.suspensionChanged) {
            $0.calibration.isSuspended = true
        }
        await store.send(.elapsedTick)
        await store.send(.resumeTapped) {
            $0.recordingState = .active
        }
        await store.receive(\.calibration.suspensionChanged) {
            $0.calibration.isSuspended = false
        }
        await store.send(.elapsedTick) {
            $0.elapsedSeconds = 2
            $0.distanceMeters = 20.0
        }
    }
}

// MARK: - State machine

@MainActor
@Suite("ActiveRideFeature — state machine")
struct ActiveRideFeatureStateMachineTests {

    private func makeStore(
        recordingState: RideRecordingState = .idle
    ) -> TestStoreOf<ActiveRideFeature> {
        TestStore(
            initialState: ActiveRideFeature.State(recordingState: recordingState)
        ) {
            ActiveRideFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.hapticsClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.locationClient = .testValue
        }
    }

    @Test("Initial state is idle")
    func initialStateIsIdle() async {
        let store = makeStore()
        #expect(store.state.recordingState == .idle)
    }

    /// The `idle → active` edge. `.task` merges seven long-lived effects (timer, HR,
    /// radar, location); `.testValue` clients hand back immediately-finishing streams
    /// and `TestClock` never advances, so nothing is emitted. Exhaustivity is off
    /// because the two `.send` child actions fire without being individually asserted.
    @Test("task transitions idle to active")
    func taskTransitionsIdleToActive() async {
        let store = makeStore(recordingState: .idle)
        store.exhaustivity = .off

        await store.send(.task) {
            $0.recordingState = .active
        }
        #expect(store.state.recordingState == .active)

        // The 1 Hz timer effect never completes on its own and `.task` returns no
        // cancellation ID, so in-flight effects must be dropped explicitly or the
        // TestStore fails on teardown.
        await store.skipInFlightEffects(strict: false)
    }

    @Test("pauseTapped only transitions from active")
    func pauseOnlyFromActive() async {
        let store = makeStore(recordingState: .active)
        await store.send(.pauseTapped) {
            $0.recordingState = .paused
        }
        await store.receive(\.calibration.suspensionChanged) {
            $0.calibration.isSuspended = true
        }
    }

    @Test("pauseTapped ignored when idle")
    func pauseIgnoredWhenIdle() async {
        let store = makeStore(recordingState: .idle)
        await store.send(.pauseTapped)
    }

    @Test("pauseTapped ignored when already paused")
    func pauseIgnoredWhenPaused() async {
        let store = makeStore(recordingState: .paused)
        await store.send(.pauseTapped)
    }

    @Test("resumeTapped only transitions from paused")
    func resumeOnlyFromPaused() async {
        let store = makeStore(recordingState: .paused)
        await store.send(.resumeTapped) {
            $0.recordingState = .active
        }
        // A store built directly at .paused never ran the .idle → .active transition,
        // so the child is still on its unsuspended default and this lands as a no-op.
        await store.receive(\.calibration.suspensionChanged)
    }

    @Test("resumeTapped ignored when active")
    func resumeIgnoredWhenActive() async {
        let store = makeStore(recordingState: .active)
        await store.send(.resumeTapped)
    }

    @Test("finishTapped presents alert when paused")
    func finishPresentsAlert() async {
        let store = makeStore(recordingState: .paused)
        await store.send(.finishTapped) {
            $0.finishAlert = AlertState {
                TextState("Finish Ride")
            } actions: {
                ButtonState(role: .destructive, action: .confirmFinish) {
                    TextState("Finish")
                }
                ButtonState(role: .cancel) {
                    TextState("Cancel")
                }
            }
        }
    }

    @Test("finishTapped ignored when active")
    func finishIgnoredWhenActive() async {
        let store = makeStore(recordingState: .active)
        await store.send(.finishTapped)
    }

    @Test("finishConfirmed transitions to ended and disconnects sensors")
    func finishConfirmedEndsRide() async {
        let disconnectCalled = LockIsolated(false)
        let store = TestStore(
            initialState: ActiveRideFeature.State(recordingState: .paused)
        ) {
            ActiveRideFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.hapticsClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.locationClient = LocationClient(
                requestAuthorization: { .authorizedWhenInUse },
                startUpdates: { AsyncStream { $0.finish() } },
                stopUpdates: { disconnectCalled.setValue(true) }
            )
        }
        await store.send(.finishTapped) {
            $0.finishAlert = AlertState {
                TextState("Finish Ride")
            } actions: {
                ButtonState(role: .destructive, action: .confirmFinish) {
                    TextState("Finish")
                }
                ButtonState(role: .cancel) {
                    TextState("Cancel")
                }
            }
        }
        await store.send(.finishAlert(.presented(.confirmFinish))) {
            $0.recordingState = .ended
            $0.finishAlert = nil
        }
        #expect(disconnectCalled.value == true)
    }

    @Test("Alert cancel does not change recording state")
    func alertCancelKeepsPaused() async {
        let store = makeStore(recordingState: .paused)
        await store.send(.finishTapped) {
            $0.finishAlert = AlertState {
                TextState("Finish Ride")
            } actions: {
                ButtonState(role: .destructive, action: .confirmFinish) {
                    TextState("Finish")
                }
                ButtonState(role: .cancel) {
                    TextState("Cancel")
                }
            }
        }
        await store.send(.finishAlert(.dismiss)) {
            $0.finishAlert = nil
        }
        #expect(store.state.recordingState == .paused)
    }

    /// PRD §8.8: auto-end after 5 minutes at zero speed. Seeded one tick below the
    /// threshold rather than ticking up to it — the counter arithmetic is covered by
    /// the timer suite, so looping here would only make the test slow.
    @Test("Auto-end triggers on the tick that reaches the zero-speed threshold")
    func autoEndTriggersAtThreshold() async {
        let threshold = ActiveRideFeature.autoEndZeroSpeedSeconds
        let store = TestStore(
            initialState: ActiveRideFeature.State(
                recordingState: .active,
                zeroSpeedSeconds: threshold - 1
            )
        ) {
            ActiveRideFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.hapticsClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.locationClient = .testValue
        }

        await store.send(.elapsedTick) {
            $0.elapsedSeconds = 1
            $0.zeroSpeedSeconds = threshold
        }
        await store.receive(.autoEndTriggered) {
            $0.recordingState = .paused
        }
        // .autoEndTriggered's own effect (.finishTapped) is merged ahead of the
        // suspension notice that `onChange` appends for the same state change.
        await store.receive(.finishTapped) {
            $0.finishAlert = AlertState {
                TextState("Finish Ride")
            } actions: {
                ButtonState(role: .destructive, action: .confirmFinish) {
                    TextState("Finish")
                }
                ButtonState(role: .cancel) {
                    TextState("Cancel")
                }
            }
        }
        await store.receive(\.calibration.suspensionChanged) {
            $0.calibration.isSuspended = true
        }
    }

    @Test("Auto-end does not trigger one tick below the threshold")
    func autoEndDoesNotTriggerBelowThreshold() async {
        let threshold = ActiveRideFeature.autoEndZeroSpeedSeconds
        let store = TestStore(
            initialState: ActiveRideFeature.State(
                recordingState: .active,
                zeroSpeedSeconds: threshold - 2
            )
        ) {
            ActiveRideFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.hapticsClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.locationClient = .testValue
        }

        // Reaches threshold - 1: no .autoEndTriggered follows, and an exhaustive
        // TestStore fails the test if one did.
        await store.send(.elapsedTick) {
            $0.elapsedSeconds = 1
            $0.zeroSpeedSeconds = threshold - 1
        }
    }

    @Test("Threshold matches the PRD's 5-minute rule")
    func autoEndThresholdIsFiveMinutes() {
        #expect(ActiveRideFeature.autoEndZeroSpeedSeconds == 300)
    }

    @Test("Zero-speed counter resets on non-zero speed")
    func zeroSpeedCounterResetsOnSpeed() async {
        let store = TestStore(
            initialState: ActiveRideFeature.State(
                recordingState: .active,
                speedKPH: 0,
                zeroSpeedSeconds: 100
            )
        ) {
            ActiveRideFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.date = .constant(testDate)
            $0.hapticsClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.locationClient = .testValue
        }

        let update = LocationUpdate(
            coordinate: Coordinate(latitude: 43.0, longitude: -89.0),
            altitude: 280.0,
            speed: 8.0,
            horizontalAccuracy: 5.0,
            heading: 0,
            timestamp: testDate
        )
        await store.send(.locationUpdated(update)) {
            $0.coordinate = Coordinate(latitude: 43.0, longitude: -89.0)
            $0.trackCoordinates = [Coordinate(latitude: 43.0, longitude: -89.0)]
            $0.altitude = 280.0
            $0.horizontalAccuracy = 5.0
            $0.heading = 0
            $0.speedKPH = 8.0 * 3.6
            $0.speedSampleCount = 1
            $0.speedSampleSum = 8.0 * 3.6
            $0.maxSpeedKPH = 8.0 * 3.6
        }
        await store.receive(.speed(.gpsSpeedReceived(8.0))) {
            $0.speed.speedMPS = 8.0
            $0.speed.activeSpeedSource = .gps
            $0.speed.latestGPSSpeedMPS = 8.0
            $0.speed.speedSamples = [SpeedSample(time: testDate, mps: 8.0)]
        }
        await store.receive(\.calibration.locationUpdated) {
            $0.calibration.isGPSUsable = true
            $0.calibration.lastFixTimestamp = update.timestamp
        }

        await store.send(.elapsedTick) {
            $0.elapsedSeconds = 1
            $0.distanceMeters = 8.0
            $0.zeroSpeedSeconds = 0
        }
    }

    @Test("Auto-end disabled skips trigger")
    func autoEndDisabledSkipsTrigger() async {
        let store = TestStore(
            initialState: ActiveRideFeature.State(
                recordingState: .active,
                zeroSpeedSeconds: ActiveRideFeature.autoEndZeroSpeedSeconds - 1,
                isAutoEndEnabled: false
            )
        ) {
            ActiveRideFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.hapticsClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.locationClient = .testValue
        }

        await store.send(.elapsedTick) {
            $0.elapsedSeconds = 1
            $0.zeroSpeedSeconds = ActiveRideFeature.autoEndZeroSpeedSeconds
        }
    }

    @Test("elapsedTick ignored when paused")
    func elapsedTickIgnoredWhenPaused() async {
        let store = makeStore(recordingState: .paused)
        await store.send(.elapsedTick)
    }

    @Test("elapsedTick ignored when idle")
    func elapsedTickIgnoredWhenIdle() async {
        let store = makeStore(recordingState: .idle)
        await store.send(.elapsedTick)
    }
}

@MainActor
@Suite("ActiveRideFeature — heart rate")
struct ActiveRideFeatureHeartRateTests {

    private func makeStore(
        _ state: ActiveRideFeature.State = ActiveRideFeature.State(recordingState: .active)
    ) -> TestStoreOf<ActiveRideFeature> {
        TestStore(initialState: state) {
            ActiveRideFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.hapticsClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.locationClient = .testValue
        }
    }

    @Test("heartRateUpdated stores bpm and derives the Karvonen zone")
    func heartRateUpdatesZone() async {
        let store = makeStore()
        // Defaults maxHR 190 / restingHR 55 → HRR 135.
        // (150 − 55) / 135 = 0.704 → zone 3 (tempo, 70–80% HRR).
        await store.send(.heartRateUpdated(150)) {
            $0.heartRateBPM = 150
            $0.hrZone = 3
        }
    }

    @Test("Unpairing clears both bpm and zone")
    func unpairClearsHeartRate() async {
        let store = makeStore(
            ActiveRideFeature.State(
                recordingState: .active,
                heartRateBPM: 150,
                hrZone: 3,
                isHRPaired: true
            )
        )
        await store.send(.hrPairingChanged(false)) {
            $0.isHRPaired = false
            $0.heartRateBPM = 0
            $0.hrZone = 0
        }
    }

    @Test("Pairing alone does not synthesise a reading")
    func pairDoesNotSetHeartRate() async {
        let store = makeStore()
        await store.send(.hrPairingChanged(true)) {
            $0.isHRPaired = true
        }
    }
}
