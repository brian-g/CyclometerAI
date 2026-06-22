import Testing
import ComposableArchitecture
import CoreLocation
@testable import Cyclometer

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

    private func makeStore() -> TestStoreOf<ActiveRideFeature> {
        TestStore(initialState: ActiveRideFeature.State()) {
            ActiveRideFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
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
            $0.altitude = 280.0
            $0.speedMPS = 8.5
            $0.horizontalAccuracy = 5.0
            $0.heading = 192.0
        }
    }

    @Test("Location updates continue while paused")
    func locationContinuesWhilePaused() async {
        let store = makeStore()
        await store.send(.locationUpdated(Self.sampleUpdate)) {
            $0.coordinate = Coordinate(latitude: 43.0731, longitude: -89.4012)
            $0.altitude = 280.0
            $0.speedMPS = 8.5
            $0.horizontalAccuracy = 5.0
            $0.heading = 192.0
        }
        await store.send(.pauseTapped) {
            $0.isPaused = true
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
            $0.altitude = 300.0
            $0.speedMPS = 12.0
            $0.horizontalAccuracy = 3.0
            $0.heading = 45.0
        }
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
        let store = TestStore(initialState: ActiveRideFeature.State()) {
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
        await store.send(.finishTapped)
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
            initialState: ActiveRideFeature.State(speedMPS: speedMPS)
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
            }
        }
    }

    @Test("Paused tick does not increment elapsedSeconds")
    func pausedTickNoElapsed() async {
        let store = makeStore()
        await store.send(.pauseTapped) {
            $0.isPaused = true
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

    @Test("Distance accumulates even while paused")
    func distanceAccumulatesWhilePaused() async {
        let store = makeStore(speedMPS: 10.0)
        await store.send(.pauseTapped) {
            $0.isPaused = true
        }
        await store.send(.elapsedTick) {
            $0.distanceMeters = 10.0
        }
        await store.send(.elapsedTick) {
            $0.distanceMeters = 20.0
        }
    }

    @Test("Negative speedMPS does not accumulate distance")
    func negativeSpeedIgnored() async {
        let store = makeStore(speedMPS: -1)
        await store.send(.elapsedTick) {
            $0.elapsedSeconds = 1
        }
    }

    @Test("Resume after pause: elapsed resumes, distance uninterrupted")
    func resumeAfterPause() async {
        let store = makeStore(speedMPS: 10.0)
        await store.send(.elapsedTick) {
            $0.elapsedSeconds = 1
            $0.distanceMeters = 10.0
        }
        await store.send(.pauseTapped) {
            $0.isPaused = true
        }
        await store.send(.elapsedTick) {
            $0.distanceMeters = 20.0
        }
        await store.send(.resumeTapped) {
            $0.isPaused = false
        }
        await store.send(.elapsedTick) {
            $0.elapsedSeconds = 2
            $0.distanceMeters = 30.0
        }
    }
}
