import Testing
import ComposableArchitecture
import CoreLocation
@testable import Cyclometer

/// Fixed clock for SpeedFeature's timestamped samples in TestStores.
private let testDate = Date(timeIntervalSince1970: 1_000_000)

/// The `VehicleTrackingRecord` `VehiclePassDetector` produces for a single radar
/// sighting at `testDate` — the fixture every suite in this file uses, since none
/// of them send a `.locationUpdated` before their radar assertions (no GPS fix,
/// zero rider speed).
private func singleSighting(mps: Double, alertLevel: AlertLevel) -> VehicleTrackingRecord {
    VehicleTrackingRecord(
        firstSeenAt: testDate, lastSeenAt: testDate,
        sampleCount: 1, positiveSampleCount: mps > 0 ? 1 : 0, positiveSampleSum: max(mps, 0),
        lastKnownCoordinate: nil, lastRiderSpeedMPS: 0, lastAlertLevel: alertLevel
    )
}

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
            $0.date = .constant(testDate)
            $0.hapticsClient = haptics
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.locationClient = .testValue
        }
    }

    @Test("Radar targets update state")
    func targetsUpdateState() async {
        let store = makeStore(clock: TestClock(), advisoryCount: LockIsolated(0))
        // Receding (negative velocity) so this purely state-focused test doesn't
        // also trip AlertLevel escalation — that's covered by its own suite.
        let targets = [
            RadarTarget(
                id: VariaRadarClient.vehicleSlotIDs[0],
                relativeVelocityMPS: -8,
                rangeMetres: 40,
                threatLevel: .danger
            )
        ]
        await store.send(.radarTargetsUpdated(targets)) {
            $0.radarTargets = targets
            $0.vehiclePassTracking = [VariaRadarClient.vehicleSlotIDs[0]: singleSighting(mps: -8, alertLevel: .clear)]
        }
    }

    @Test("Active connection sets paired badge")
    func activeSetsPaired() async {
        let store = makeStore(clock: TestClock(), advisoryCount: LockIsolated(0))
        await store.send(.radarConnectionChanged(.active)) {
            $0.isRadarPaired = true
            $0.radarConnectionState = .active
            $0.wasRadarEverPaired = true
        }
    }

    @Test("Disconnect during ride: badge flips and L1 advisory haptic fires once after 10s")
    func disconnectBadgeAndHaptic() async {
        let clock = TestClock()
        let advisoryCount = LockIsolated(0)
        let store = makeStore(clock: clock, advisoryCount: advisoryCount)

        await store.send(.radarConnectionChanged(.active)) {
            $0.isRadarPaired = true
            $0.radarConnectionState = .active
            $0.wasRadarEverPaired = true
        }
        // Receding (negative velocity) so this test stays focused on the disconnect
        // haptic path rather than also exercising AlertLevel escalation.
        await store.send(.radarTargetsUpdated([
            RadarTarget(
                id: VariaRadarClient.vehicleSlotIDs[0],
                relativeVelocityMPS: -5,
                rangeMetres: 60,
                threatLevel: .warning
            )
        ])) {
            $0.radarTargets = [
                RadarTarget(
                    id: VariaRadarClient.vehicleSlotIDs[0],
                    relativeVelocityMPS: -5,
                    rangeMetres: 60,
                    threatLevel: .warning
                )
            ]
            $0.vehiclePassTracking = [VariaRadarClient.vehicleSlotIDs[0]: singleSighting(mps: -5, alertLevel: .clear)]
        }

        // Badge stays paired during the 10s grace window.
        await store.send(.radarConnectionChanged(.reconnecting)) {
            $0.radarConnectionState = .reconnecting
        }
        await clock.advance(by: .seconds(10))
        await store.receive(\.radarReconnectTimedOut) {
            $0.isRadarPaired = false
            $0.radarTargets = []
            $0.radarConnectionState = .disconnected
            $0.vehiclePassTracking = [:]
        }
        await store.receive(\.alertOrchestrator.alertLevelChanged) {
            $0.alertOrchestrator.activeAlertLevel = .advisory
            $0.alertOrchestrator.lastAlertDispatchAt = [.advisory: testDate]
        }
        #expect(advisoryCount.value == 1)

        // A second .reconnecting while unpaired does not re-arm the timer.
        await store.send(.radarConnectionChanged(.reconnecting)) {
            $0.radarConnectionState = .reconnecting
        }
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
            $0.radarConnectionState = .active
            $0.wasRadarEverPaired = true
        }
        await store.send(.radarConnectionChanged(.reconnecting)) {
            $0.radarConnectionState = .reconnecting
        }
        await clock.advance(by: .seconds(9))
        await store.send(.radarConnectionChanged(.active)) {
            $0.radarConnectionState = .active
        }
        await clock.advance(by: .seconds(60))
        #expect(advisoryCount.value == 0)
    }

    @Test("Terminal disconnect clears badge and targets immediately")
    func terminalDisconnect() async {
        let store = makeStore(clock: TestClock(), advisoryCount: LockIsolated(0))
        await store.send(.radarConnectionChanged(.active)) {
            $0.isRadarPaired = true
            $0.radarConnectionState = .active
            $0.wasRadarEverPaired = true
        }
        await store.send(.radarConnectionChanged(.disconnected)) {
            $0.isRadarPaired = false
            $0.radarTargets = []
            $0.radarConnectionState = .disconnected
        }
        await store.receive(\.alertOrchestrator.hardDisconnected)
    }

    @Test("Sidebar hidden until radar has ever paired this ride")
    func sidebarHiddenUntilEverPaired() async {
        let store = makeStore(clock: TestClock(), advisoryCount: LockIsolated(0))
        #expect(store.state.isRadarSidebarVisible == false)
        #expect(store.state.isRadarOffline == false)
    }

    @Test("Sidebar shows offline during the reconnect grace window, not stale targets")
    func sidebarOfflineDuringGraceWindow() async {
        let clock = TestClock()
        let store = makeStore(clock: clock, advisoryCount: LockIsolated(0))

        await store.send(.radarConnectionChanged(.active)) {
            $0.isRadarPaired = true
            $0.radarConnectionState = .active
            $0.wasRadarEverPaired = true
        }
        let targets = [
            RadarTarget(
                id: VariaRadarClient.vehicleSlotIDs[0],
                relativeVelocityMPS: -5,
                rangeMetres: 60,
                threatLevel: .warning
            )
        ]
        await store.send(.radarTargetsUpdated(targets)) {
            $0.radarTargets = targets
            $0.vehiclePassTracking = [VariaRadarClient.vehicleSlotIDs[0]: singleSighting(mps: -5, alertLevel: .clear)]
        }

        await store.send(.radarConnectionChanged(.reconnecting)) {
            $0.radarConnectionState = .reconnecting
        }
        // Still "paired" for haptic-timer purposes, and radarTargets is untouched —
        // but the sidebar must already report offline rather than show these stale
        // colored targets (#137).
        #expect(store.state.isRadarPaired == true)
        #expect(store.state.radarTargets == targets)
        #expect(store.state.isRadarSidebarVisible == true)
        #expect(store.state.isRadarOffline == true)

        await clock.advance(by: .seconds(10))
        await store.receive(\.radarReconnectTimedOut) {
            $0.isRadarPaired = false
            $0.radarTargets = []
            $0.radarConnectionState = .disconnected
            $0.vehiclePassTracking = [:]
        }
        await store.receive(\.alertOrchestrator.alertLevelChanged) {
            $0.alertOrchestrator.activeAlertLevel = .advisory
            $0.alertOrchestrator.lastAlertDispatchAt = [.advisory: testDate]
        }
        // Sidebar stays visible (grayed), not hidden, past the grace window too.
        #expect(store.state.isRadarSidebarVisible == true)
        #expect(store.state.isRadarOffline == true)

        await store.send(.radarConnectionChanged(.active)) {
            $0.isRadarPaired = true
            $0.radarConnectionState = .active
        }
        #expect(store.state.isRadarOffline == false)
    }

    @Test("Hard disconnect keeps the sidebar visible (grayed), not hidden")
    func hardDisconnectKeepsSidebarVisible() async {
        let store = makeStore(clock: TestClock(), advisoryCount: LockIsolated(0))
        await store.send(.radarConnectionChanged(.active)) {
            $0.isRadarPaired = true
            $0.radarConnectionState = .active
            $0.wasRadarEverPaired = true
        }
        await store.send(.radarConnectionChanged(.disconnected)) {
            $0.isRadarPaired = false
            $0.radarTargets = []
            $0.radarConnectionState = .disconnected
        }
        await store.receive(\.alertOrchestrator.hardDisconnected)
        #expect(store.state.isRadarSidebarVisible == true)
        #expect(store.state.isRadarOffline == true)
    }
}

// MARK: - Alert escalation wiring

/// #155: thin wiring coverage confirming `ActiveRideFeature` correctly routes into
/// `AlertOrchestratorFeature` — the full L0-L3 dispatch mechanism (guards, haptic/audio
/// effects, the danger-repeat loop) has its own isolated coverage in
/// `AlertOrchestratorFeatureTests`, extracted from this suite in #155.
/// `RadarTarget.threatLevel` is pinned to `.allClear` throughout — that field only
/// drives `isCalibrationSuspended` (a separate concern, its own suite above), and
/// these tests care about `relativeVelocityMPS` only.
@MainActor
@Suite("ActiveRideFeature — alert escalation wiring")
struct ActiveRideFeatureAlertEscalationTests {

    private static func vehicle(mps: Double, slot: Int = 0) -> RadarTarget {
        RadarTarget(
            id: VariaRadarClient.vehicleSlotIDs[slot],
            relativeVelocityMPS: mps,
            rangeMetres: 40,
            threatLevel: .allClear
        )
    }

    private func makeStore(clock: TestClock<Duration>) -> TestStoreOf<ActiveRideFeature> {
        TestStore(initialState: ActiveRideFeature.State(recordingState: .active)) {
            ActiveRideFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date = .constant(testDate)
            $0.hapticsClient = .testValue
            $0.audioClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.locationClient = .testValue
        }
    }

    @Test("Radar targets that change the derived level forward .alertLevelChanged to the orchestrator")
    func radarTargetsUpdatedForwardsLevelChange() async {
        let store = makeStore(clock: TestClock())
        let targets = [Self.vehicle(mps: 2)]

        await store.send(.radarTargetsUpdated(targets)) {
            $0.radarTargets = targets
            $0.vehiclePassTracking = [VariaRadarClient.vehicleSlotIDs[0]: singleSighting(mps: 2, alertLevel: .advisory)]
        }
        await store.receive(\.alertOrchestrator.alertLevelChanged) {
            $0.alertOrchestrator.activeAlertLevel = .advisory
            $0.alertOrchestrator.lastAlertDispatchAt = [.advisory: testDate]
        }
    }

    @Test("Radar targets that don't change the derived level never reach the orchestrator")
    func radarTargetsUpdatedSkipsOrchestratorWhenLevelUnchanged() async {
        let store = makeStore(clock: TestClock())
        // Receding (negative velocity): derived level stays .clear, matching the
        // orchestrator's initial state, so the `!=` guard skips the send entirely.
        let targets = [Self.vehicle(mps: -8)]

        await store.send(.radarTargetsUpdated(targets)) {
            $0.radarTargets = targets
            $0.vehiclePassTracking = [VariaRadarClient.vehicleSlotIDs[0]: singleSighting(mps: -8, alertLevel: .clear)]
        }
    }

    @Test("Hard disconnect forwards .hardDisconnected to the orchestrator")
    func disconnectForwardsHardDisconnected() async {
        let store = makeStore(clock: TestClock())

        await store.send(.radarTargetsUpdated([Self.vehicle(mps: 20 / 3.6)])) {
            $0.radarTargets = [Self.vehicle(mps: 20 / 3.6)]
            $0.vehiclePassTracking = [VariaRadarClient.vehicleSlotIDs[0]: singleSighting(mps: 20 / 3.6, alertLevel: .caution)]
        }
        await store.receive(\.alertOrchestrator.alertLevelChanged) {
            $0.alertOrchestrator.activeAlertLevel = .caution
            $0.alertOrchestrator.lastAlertDispatchAt = [.caution: testDate]
        }

        await store.send(.radarConnectionChanged(.disconnected)) {
            $0.isRadarPaired = false
            $0.radarTargets = []
            $0.radarConnectionState = .disconnected
            $0.vehiclePassTracking = [:]
        }
        await store.receive(\.alertOrchestrator.hardDisconnected) {
            $0.alertOrchestrator.activeAlertLevel = .clear
            $0.alertOrchestrator.lastAlertDispatchAt = [:]
        }
    }

    @Test("Reconnect timeout forwards .alertLevelChanged(.advisory) to the orchestrator unconditionally")
    func reconnectTimeoutForwardsAdvisoryUnconditionally() async {
        let clock = TestClock()
        let store = makeStore(clock: clock)

        await store.send(.radarConnectionChanged(.active)) {
            $0.isRadarPaired = true
            $0.radarConnectionState = .active
            $0.wasRadarEverPaired = true
        }
        await store.send(.radarConnectionChanged(.reconnecting)) {
            $0.radarConnectionState = .reconnecting
        }
        await clock.advance(by: .seconds(10))
        await store.receive(\.radarReconnectTimedOut) {
            $0.isRadarPaired = false
            $0.radarTargets = []
            $0.radarConnectionState = .disconnected
        }
        await store.receive(\.alertOrchestrator.alertLevelChanged) {
            $0.alertOrchestrator.activeAlertLevel = .advisory
            $0.alertOrchestrator.lastAlertDispatchAt = [.advisory: testDate]
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
        await store.receive(\.trackRecorder.pauseRecording)
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
        await store.send(.locationAuthorizationResult(.granted)) {
            $0.isLocationAvailable = true
        }
    }

    @Test("Authorization grantedAlways also sets isLocationAvailable true")
    func authAlways() async {
        let store = makeStore()
        await store.send(.locationAuthorizationResult(.grantedAlways)) {
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
            $0.date = .constant(testDate)
            $0.hapticsClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.permissionsClient = .mock(initial: [.locationWhenInUse: .granted])
            $0.locationClient = LocationClient(
                startUpdates: { AsyncStream { $0.finish() } },
                stopUpdates: { stopCalled.setValue(true) }
            )
        }
        await store.send(.pauseTapped) {
            $0.recordingState = .paused
        }
        await store.receive(\.trackRecorder.pauseRecording)
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
        speedMPS: Double = 0,
        persistenceClient: PersistenceClient = .testValue
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
            $0.persistenceClient = persistenceClient
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
        await store.receive(\.trackRecorder.pauseRecording)
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
        await store.receive(\.trackRecorder.pauseRecording)
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
        await store.receive(\.trackRecorder.pauseRecording)
        await store.receive(\.calibration.suspensionChanged) {
            $0.calibration.isSuspended = true
        }
        await store.send(.elapsedTick)
        await store.send(.resumeTapped) {
            $0.recordingState = .active
        }
        await store.receive(\.trackRecorder.resumeRecording) {
            $0.trackRecorder.isRecording = true
        }
        await store.receive(\.calibration.suspensionChanged) {
            $0.calibration.isSuspended = false
        }
        await store.send(.elapsedTick) {
            $0.elapsedSeconds = 2
            $0.distanceMeters = 20.0
        }
    }

    @Test("Checkpoint fires exactly once per 30 ticks while active")
    func checkpointFiresEvery30Ticks() async {
        // Non-zero speed throughout, so zeroSpeedSeconds never accumulates far
        // enough to trip auto-pause (10s) or auto-end (300s) — this test is only
        // about the 30s checkpoint cadence.
        let checkpointCount = LockIsolated(0)
        let store = makeStore(speedMPS: 10.0, persistenceClient: .mock(
            onUpdateRideSummary: { _ in checkpointCount.withValue { $0 += 1 } }
        ))
        for tick in 1...29 {
            await store.send(.elapsedTick) {
                $0.elapsedSeconds = tick
                $0.distanceMeters = Double(tick) * 10.0
            }
        }
        #expect(checkpointCount.value == 0)

        await store.send(.elapsedTick) {
            $0.elapsedSeconds = 30
            $0.distanceMeters = 300.0
        }
        await store.receive(\.trackRecorder.checkpointFired)
        #expect(checkpointCount.value == 1)

        for tick in 31...59 {
            await store.send(.elapsedTick) {
                $0.elapsedSeconds = tick
                $0.distanceMeters = Double(tick) * 10.0
            }
        }
        #expect(checkpointCount.value == 1)

        await store.send(.elapsedTick) {
            $0.elapsedSeconds = 60
            $0.distanceMeters = 600.0
        }
        await store.receive(\.trackRecorder.checkpointFired)
        #expect(checkpointCount.value == 2)
    }

    @Test("No checkpoint fires while paused")
    func noCheckpointWhilePaused() async {
        let checkpointCount = LockIsolated(0)
        let store = makeStore(persistenceClient: .mock(
            onUpdateRideSummary: { _ in checkpointCount.withValue { $0 += 1 } }
        ))
        await store.send(.pauseTapped) {
            $0.recordingState = .paused
        }
        await store.receive(\.trackRecorder.pauseRecording)
        await store.receive(\.calibration.suspensionChanged) {
            $0.calibration.isSuspended = true
        }
        // pauseTapped itself persists the .paused transition (#171 review) — that's
        // the one write expected here; the 30 no-op ticks below must not add more.
        #expect(checkpointCount.value == 1)
        for _ in 0..<30 {
            await store.send(.elapsedTick)
        }
        #expect(checkpointCount.value == 1)
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
            $0.date = .constant(testDate)
            $0.uuid = .incrementing
            $0.hapticsClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.locationClient = .testValue
        }
    }

    /// Quarantines `AppPreferences` in its own in-memory storage, the same way
    /// `ActiveRideFeatureHeartRateTests` quarantines `RiderProfile` — otherwise
    /// `state.preferences.isAutoPauseEnabled` would read whatever
    /// `app-preferences.json` happens to exist on the machine running the suite.
    /// Needed only by tests that push `zeroSpeedSeconds` far enough for auto-pause
    /// (#102) to interact with what the test is actually isolating.
    ///
    /// `state` is an autoclosure, evaluated *inside* the dependency scope below —
    /// otherwise `ActiveRideFeature.State`'s `@SharedReader(.appPreferences)` would
    /// resolve against the ambient live storage before this function ever runs.
    private func makeStore(
        state: @autoclosure () -> ActiveRideFeature.State,
        isAutoPauseEnabled: Bool
    ) -> TestStoreOf<ActiveRideFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.isAutoPauseEnabled = isAutoPauseEnabled }
            return TestStore(initialState: state()) {
                ActiveRideFeature()
            } withDependencies: {
                $0.continuousClock = TestClock()
                $0.hapticsClient = .testValue
                $0.variaRadarClient = .testValue
                $0.bleHRClient = .testValue
                $0.locationClient = .testValue
                $0.defaultFileStorage = storage
            }
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

    @Test("task creates a Ride with a deterministic id via persistenceClient")
    func taskCreatesRide() async {
        let created = LockIsolated<(UUID, Date)?>(nil)
        let store = TestStore(
            initialState: ActiveRideFeature.State(recordingState: .idle)
        ) {
            ActiveRideFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.date = .constant(testDate)
            $0.uuid = .incrementing
            $0.hapticsClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.locationClient = .testValue
            $0.persistenceClient = .mock(onCreateRide: { created.setValue(($0, $1)) })
        }
        store.exhaustivity = .off

        await store.send(.task) {
            $0.recordingState = .active
            $0.rideId = UUID(0)
        }
        #expect(created.value?.0 == UUID(0))
        #expect(created.value?.1 == testDate)

        await store.skipInFlightEffects(strict: false)
    }

    @Test("pauseTapped only transitions from active")
    func pauseOnlyFromActive() async {
        let store = makeStore(recordingState: .active)
        await store.send(.pauseTapped) {
            $0.recordingState = .paused
        }
        await store.receive(\.trackRecorder.pauseRecording)
        await store.receive(\.calibration.suspensionChanged) {
            $0.calibration.isSuspended = true
        }
    }

    @Test("pauseTapped persists the paused recordingState")
    func pauseTappedPersistsPausedState() async {
        let updatedSummary = LockIsolated<RideSummaryUpdate?>(nil)
        let rideId = UUID()
        let store = TestStore(
            initialState: ActiveRideFeature.State(rideId: rideId, recordingState: .active, distanceMeters: 250)
        ) {
            ActiveRideFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.hapticsClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.locationClient = .testValue
            $0.persistenceClient = .mock(onUpdateRideSummary: { updatedSummary.setValue($0) })
        }
        await store.send(.pauseTapped) {
            $0.recordingState = .paused
        }
        await store.receive(\.trackRecorder.pauseRecording)
        await store.receive(\.calibration.suspensionChanged) {
            $0.calibration.isSuspended = true
        }
        #expect(updatedSummary.value?.rideId == rideId)
        #expect(updatedSummary.value?.recordingState == .paused)
        #expect(updatedSummary.value?.distanceMeters == 250)
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
        await store.receive(\.trackRecorder.resumeRecording) {
            $0.trackRecorder.isRecording = true
        }
        // A store built directly at .paused never ran the .idle → .active transition,
        // so the child is still on its unsuspended default and this lands as a no-op.
        await store.receive(\.calibration.suspensionChanged)
    }

    @Test("resumeTapped persists the active recordingState")
    func resumeTappedPersistsActiveState() async {
        let updatedSummary = LockIsolated<RideSummaryUpdate?>(nil)
        let rideId = UUID()
        let store = TestStore(
            initialState: ActiveRideFeature.State(rideId: rideId, recordingState: .paused)
        ) {
            ActiveRideFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.hapticsClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.locationClient = .testValue
            $0.persistenceClient = .mock(onUpdateRideSummary: { updatedSummary.setValue($0) })
        }
        await store.send(.resumeTapped) {
            $0.recordingState = .active
        }
        await store.receive(\.trackRecorder.resumeRecording) {
            $0.trackRecorder.isRecording = true
        }
        await store.receive(\.calibration.suspensionChanged)
        #expect(updatedSummary.value?.rideId == rideId)
        #expect(updatedSummary.value?.recordingState == .active)
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
        let finalizedRide = LockIsolated<(UUID, Date, RideSummaryUpdate)?>(nil)
        let rideId = UUID()
        let store = TestStore(
            initialState: ActiveRideFeature.State(rideId: rideId, recordingState: .paused, distanceMeters: 500)
        ) {
            ActiveRideFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.date = .constant(testDate)
            $0.hapticsClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.permissionsClient = .mock(initial: [.locationWhenInUse: .granted])
            $0.locationClient = LocationClient(
                startUpdates: { AsyncStream { $0.finish() } },
                stopUpdates: { disconnectCalled.setValue(true) }
            )
            $0.persistenceClient = .mock(
                onFinalizeRide: { finalizedRide.setValue(($0, $1, $2)) }
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
        #expect(finalizedRide.value?.0 == rideId)
        #expect(finalizedRide.value?.1 == testDate)
        #expect(finalizedRide.value?.2.rideId == rideId)
        #expect(finalizedRide.value?.2.distanceMeters == 500)
        #expect(finalizedRide.value?.2.recordingState == .ended)
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
    /// the timer suite, so looping here would only make the test slow. Auto-pause
    /// (#102) is disabled so this test isolates auto-end — otherwise the same
    /// zero-speed counter would trip auto-pause first, long before 300s.
    @Test("Auto-end triggers on the tick that reaches the zero-speed threshold")
    func autoEndTriggersAtThreshold() async {
        let threshold = ActiveRideFeature.autoEndZeroSpeedSeconds
        let store = makeStore(
            state: ActiveRideFeature.State(
                recordingState: .active,
                zeroSpeedSeconds: threshold - 1
            ),
            isAutoPauseEnabled: false
        )

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
        let store = makeStore(
            state: ActiveRideFeature.State(
                recordingState: .active,
                zeroSpeedSeconds: threshold - 2
            ),
            isAutoPauseEnabled: false
        )

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
        await store.receive(\.trackRecorder.timerTick)
    }

    @Test("Auto-end disabled skips trigger")
    func autoEndDisabledSkipsTrigger() async {
        let store = makeStore(
            state: ActiveRideFeature.State(
                recordingState: .active,
                zeroSpeedSeconds: ActiveRideFeature.autoEndZeroSpeedSeconds - 1,
                isAutoEndEnabled: false
            ),
            isAutoPauseEnabled: false
        )

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

// MARK: - Auto-pause

/// S12/#102: auto-pause fires at a much shorter zero-speed threshold than
/// auto-end, so a rider stopped at a light pauses rather than waiting five
/// minutes. Only a pause auto-pause itself triggered is eligible to auto-resume —
/// a manual Pause tap always requires a manual Resume.
@MainActor
@Suite("ActiveRideFeature — auto-pause")
struct ActiveRideFeatureAutoPauseTests {

    /// Quarantines `AppPreferences` in its own in-memory storage — see the same
    /// helper on `ActiveRideFeatureStateMachineTests` for why this is necessary,
    /// and why `state` is an autoclosure.
    private func makeStore(
        state: @autoclosure () -> ActiveRideFeature.State,
        isAutoPauseEnabled: Bool = true
    ) -> TestStoreOf<ActiveRideFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.isAutoPauseEnabled = isAutoPauseEnabled }
            return TestStore(initialState: state()) {
                ActiveRideFeature()
            } withDependencies: {
                $0.continuousClock = TestClock()
                $0.date = .constant(testDate)
                $0.hapticsClient = .testValue
                $0.variaRadarClient = .testValue
                $0.bleHRClient = .testValue
                $0.locationClient = .testValue
                $0.defaultFileStorage = storage
            }
        }
    }

    @Test("Auto-pause triggers on the tick that reaches the zero-speed threshold")
    func autoPauseTriggersAtThreshold() async {
        let threshold = ActiveRideFeature.autoPauseZeroSpeedSeconds
        let store = makeStore(
            state: ActiveRideFeature.State(recordingState: .active, zeroSpeedSeconds: threshold - 1)
        )

        await store.send(.elapsedTick) {
            $0.elapsedSeconds = 1
            $0.zeroSpeedSeconds = threshold
        }
        await store.receive(.autoPauseTriggered) {
            $0.recordingState = .paused
            $0.isAutoPaused = true
        }
        await store.receive(\.calibration.suspensionChanged) {
            $0.calibration.isSuspended = true
        }
    }

    @Test("Auto-pause does not trigger one tick below the threshold")
    func autoPauseDoesNotTriggerBelowThreshold() async {
        let threshold = ActiveRideFeature.autoPauseZeroSpeedSeconds
        let store = makeStore(
            state: ActiveRideFeature.State(recordingState: .active, zeroSpeedSeconds: threshold - 2)
        )

        await store.send(.elapsedTick) {
            $0.elapsedSeconds = 1
            $0.zeroSpeedSeconds = threshold - 1
        }
    }

    @Test("Auto-pause disabled skips trigger")
    func autoPauseDisabledSkipsTrigger() async {
        let threshold = ActiveRideFeature.autoPauseZeroSpeedSeconds
        let store = makeStore(
            state: ActiveRideFeature.State(recordingState: .active, zeroSpeedSeconds: threshold - 1),
            isAutoPauseEnabled: false
        )

        await store.send(.elapsedTick) {
            $0.elapsedSeconds = 1
            $0.zeroSpeedSeconds = threshold
        }
    }

    /// Both thresholds are eligible on the same tick when a ride sits idle long
    /// enough; auto-pause is checked first, so it wins and auto-end's own 5-minute
    /// counter never gets the chance to run (it only advances from `.active`).
    @Test("Auto-pause preempts auto-end when both thresholds are reached together")
    func autoPausePreemptsAutoEnd() async {
        let store = makeStore(
            state: ActiveRideFeature.State(
                recordingState: .active,
                zeroSpeedSeconds: ActiveRideFeature.autoEndZeroSpeedSeconds - 1
            )
        )

        await store.send(.elapsedTick) {
            $0.elapsedSeconds = 1
            $0.zeroSpeedSeconds = ActiveRideFeature.autoEndZeroSpeedSeconds
        }
        await store.receive(.autoPauseTriggered) {
            $0.recordingState = .paused
            $0.isAutoPaused = true
        }
        await store.receive(\.calibration.suspensionChanged) {
            $0.calibration.isSuspended = true
        }
    }

    @Test("Motion resumes a ride that auto-pause itself paused")
    func motionResumesAnAutoPausedRide() async {
        let store = makeStore(
            state: ActiveRideFeature.State(
                recordingState: .paused,
                zeroSpeedSeconds: ActiveRideFeature.autoPauseZeroSpeedSeconds,
                isAutoPaused: true
            )
        )
        store.exhaustivity = .off

        await store.send(.speed(.gpsSpeedReceived(5.0)))

        #expect(store.state.recordingState == .active)
        #expect(store.state.isAutoPaused == false)
        #expect(store.state.zeroSpeedSeconds == 0)
    }

    @Test("Motion does not resume a ride the rider paused manually")
    func motionDoesNotResumeAManuallyPausedRide() async {
        let store = makeStore(
            state: ActiveRideFeature.State(recordingState: .paused, isAutoPaused: false)
        )
        store.exhaustivity = .off

        await store.send(.speed(.gpsSpeedReceived(5.0)))

        #expect(store.state.recordingState == .paused)
        #expect(store.state.isAutoPaused == false)
    }
}

@MainActor
@Suite("ActiveRideFeature — heart rate")
struct ActiveRideFeatureHeartRateTests {

    /// The fixed `@Dependency(\.date)` every store in this suite is built with.
    private static let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    /// Storage is quarantined per store because the zone now derives from the shared
    /// `RiderProfile` (#96) — without this the assertions would depend on whatever
    /// `rider-profile.json` happens to exist on the machine. The state is built
    /// inside the same scope as the seed, since `@SharedReader` resolves when the
    /// state is constructed.
    private func makeStore(
        profile: RiderProfile = RiderProfile(),
        healthKitClient: HealthKitClient = .testValue,
        _ state: @autoclosure () -> ActiveRideFeature.State
            = ActiveRideFeature.State(recordingState: .active)
    ) -> TestStoreOf<ActiveRideFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.riderProfile) var stored
            $stored.withLock { $0 = profile }
            return TestStore(initialState: state()) {
                ActiveRideFeature()
            } withDependencies: {
                $0.continuousClock = TestClock()
                $0.hapticsClient = .testValue
                $0.variaRadarClient = .testValue
                $0.bleHRClient = .testValue
                $0.locationClient = .testValue
                $0.healthKitClient = healthKitClient
                $0.date = .constant(Self.fixedNow)
                $0.uuid = .incrementing
                $0.defaultFileStorage = storage
            }
        }
    }

    @Test("heartRateUpdated stores bpm and derives the Karvonen zone")
    func heartRateUpdatesZone() async {
        let store = makeStore()
        // An empty profile resolves to maxHR 190 / restingHR 60 → HRR 130.
        // (150 − 60) / 130 = 0.692 → zone 2 (endurance, 60–70% HRR).
        await store.send(.heartRateUpdated(150)) {
            $0.heartRateBPM = 150
            $0.hrZone = 2
            $0.hrSampleCount = 1
            $0.hrSampleSum = 150
            $0.maxHeartRateBPM = 150
        }
    }

    /// The wiring #96 added: the dashboard reads the rider's profile rather than a
    /// hardcoded pair, so the same bpm lands in a different zone for a fitter rider.
    @Test("An override moves the same reading into a different zone")
    func overrideChangesDerivedZone() async {
        let store = makeStore(
            profile: RiderProfile(restingOverrideBPM: 45, maxOverrideBPM: 200)
        )
        // HRR 155 → (165 − 45) / 155 = 0.774 → zone 3. The same reading is zone 4
        // under the defaults ((165 − 60) / 130 = 0.808), which is the point.
        await store.send(.heartRateUpdated(165)) {
            $0.heartRateBPM = 165
            $0.hrZone = 3
            $0.hrSampleCount = 1
            $0.hrSampleSum = 165
            $0.maxHeartRateBPM = 165
        }
        #expect(store.state.riderProfile.resolvedMaxBPM() == 200)
        #expect(store.state.riderProfile.resolvedRestingBPM() == 45)
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

    // MARK: - HealthKit-sourced resting/max (#160)

    @Test("A HealthKit-scripted resting HR and date of birth resolve the zone, not the 60/190 defaults")
    func healthKitTermsResolveZone() async {
        let store = makeStore(healthKitClient: .mock(
            restingHeartRate: 48,
            dateOfBirth: DateComponents(year: 1990, month: 1, day: 1)
        ))
        store.exhaustivity = .off

        await store.send(.task)
        await store.receive(\.healthProfileFetched) {
            $0.healthRestingBPM = 48
            // Fixed test clock is 2027-01-15; already 37 by 1990-01-01 → 220 − 37 = 183.
            $0.healthMaxBPM = 183
        }
        // HRR 135 → (150 − 48) / 135 = 0.756 → zone 3, not the zone 2 the 60/190
        // defaults would give the same reading.
        await store.send(.heartRateUpdated(150)) {
            $0.heartRateBPM = 150
            $0.hrZone = 3
        }
        await store.skipInFlightEffects(strict: false)
    }

    @Test("A manual override still wins over a HealthKit-scripted value")
    func overrideBeatsHealthKitTerm() async {
        let store = makeStore(
            profile: RiderProfile(restingOverrideBPM: 45, maxOverrideBPM: 200),
            healthKitClient: .mock(restingHeartRate: 48, dateOfBirth: DateComponents(year: 1990, month: 1, day: 1))
        )
        store.exhaustivity = .off

        await store.send(.task)
        await store.receive(\.healthProfileFetched) {
            $0.healthRestingBPM = 48
            $0.healthMaxBPM = 183
        }
        // Same case as `overrideChangesDerivedZone`: HRR 155 → (165 − 45) / 155 =
        // 0.774 → zone 3, using the override pair rather than the fetched 48/183.
        await store.send(.heartRateUpdated(165)) {
            $0.heartRateBPM = 165
            $0.hrZone = 3
        }
        await store.skipInFlightEffects(strict: false)
    }

    @Test("No date of birth on file falls back to the 190 default, not a crash or placeholder")
    func noDateOfBirthFallsBackToDefaultMax() async {
        let store = makeStore(healthKitClient: .mock(restingHeartRate: 48))
        store.exhaustivity = .off

        await store.send(.task)
        await store.receive(\.healthProfileFetched) {
            $0.healthRestingBPM = 48
            $0.healthMaxBPM = nil
        }
        #expect(store.state.riderProfile.resolvedMaxBPM(healthMax: store.state.healthMaxBPM) == 190)
        await store.skipInFlightEffects(strict: false)
    }

    // MARK: - BLE → HealthKit fallback (#161)

    @Test("A live HealthKit BPM reaches the dashboard when nothing is paired")
    func healthKitStreamFeedsDashboardWhenUnpaired() async {
        let store = makeStore(healthKitClient: .mock(heartRateSamples: [72]))
        store.exhaustivity = .off

        await store.send(.task)
        // An empty profile resolves to maxHR 190 / restingHR 60 → HRR 130.
        // (72 − 60) / 130 = 0.092 → zone 1.
        await store.receive(\.healthKitHeartRateUpdated) {
            $0.healthKitHRSample = HealthKitHRSample(bpm: 72, receivedAt: Self.fixedNow)
            $0.heartRateBPM = 72
            $0.hrZone = 1
        }
        #expect(store.state.hrSource == .healthKit)
        await store.skipInFlightEffects(strict: false)
    }

    @Test("BLE takes precedence over a concurrent HealthKit reading")
    func bleTakesPrecedenceOverConcurrentHealthKit() async {
        let store = makeStore(
            ActiveRideFeature.State(recordingState: .active, heartRateBPM: 150, hrZone: 2, isHRPaired: true)
        )
        // Recorded only as the shadow value — the displayed bpm/zone don't move.
        await store.send(.healthKitHeartRateUpdated(72)) {
            $0.healthKitHRSample = HealthKitHRSample(bpm: 72, receivedAt: Self.fixedNow)
        }
        #expect(store.state.heartRateBPM == 150)
        #expect(store.state.hrZone == 2)
        #expect(store.state.hrSource == .bleStrap)
    }

    @Test("Disconnecting the BLE strap falls back to the last known HealthKit reading")
    func disconnectFallsBackToHealthKitShadowValue() async {
        let store = makeStore(
            ActiveRideFeature.State(recordingState: .active, heartRateBPM: 150, hrZone: 2, isHRPaired: true)
        )
        await store.send(.healthKitHeartRateUpdated(72)) {
            $0.healthKitHRSample = HealthKitHRSample(bpm: 72, receivedAt: Self.fixedNow)
        }
        // Same zone math as `healthKitStreamFeedsDashboardWhenUnpaired`: 72 → zone 1.
        await store.send(.hrPairingChanged(false)) {
            $0.isHRPaired = false
            $0.heartRateBPM = 72
            $0.hrZone = 1
            $0.hrSampleCount = 1
            $0.hrSampleSum = 72
            $0.maxHeartRateBPM = 72
        }
        #expect(store.state.hrSource == .healthKit)
    }

    @Test("A HealthKit reading older than the staleness window is not promoted on disconnect")
    func staleHealthKitSampleIsNotPromotedOnDisconnect() async {
        let store = makeStore(
            ActiveRideFeature.State(
                recordingState: .active,
                heartRateBPM: 150,
                hrZone: 2,
                isHRPaired: true,
                healthKitHRSample: HealthKitHRSample(
                    bpm: 72,
                    receivedAt: Self.fixedNow.addingTimeInterval(-ActiveRideFeature.healthKitHRStalenessWindow)
                )
            )
        )
        await store.send(.hrPairingChanged(false)) {
            $0.isHRPaired = false
            $0.healthKitHRSample = nil
            $0.heartRateBPM = 0
            $0.hrZone = 0
        }
        #expect(store.state.hrSource == .none)
    }

    @Test("A HealthKit reading expires on its own once it goes stale as the active source")
    func staleHealthKitSampleExpiresOnElapsedTick() async {
        let store = makeStore(
            ActiveRideFeature.State(
                recordingState: .active,
                heartRateBPM: 72,
                hrZone: 1,
                isHRPaired: false,
                healthKitHRSample: HealthKitHRSample(
                    bpm: 72,
                    receivedAt: Self.fixedNow.addingTimeInterval(-ActiveRideFeature.healthKitHRStalenessWindow)
                )
            )
        )
        await store.send(.elapsedTick) {
            $0.healthKitHRSample = nil
            $0.heartRateBPM = 0
            $0.hrZone = 0
            $0.elapsedSeconds = 1
            $0.zeroSpeedSeconds = 1
        }
        #expect(store.state.hrSource == .none)
    }

    @Test("Reconnecting the BLE strap switches back over HealthKit immediately")
    func reconnectingSwitchesBackToBLE() async {
        let store = makeStore(
            ActiveRideFeature.State(
                recordingState: .active,
                heartRateBPM: 72,
                hrZone: 1,
                isHRPaired: false,
                healthKitHRSample: HealthKitHRSample(bpm: 72, receivedAt: Self.fixedNow)
            )
        )
        #expect(store.state.hrSource == .healthKit)
        // `hrSource` is computed, so this flips the instant pairing does — no new
        // BLE sample has to arrive first.
        await store.send(.hrPairingChanged(true)) {
            $0.isHRPaired = true
        }
        #expect(store.state.hrSource == .bleStrap)
    }

    @Test("With neither source available, the dashboard reports no HR source")
    func noSourceShowsNoHRSource() async {
        let store = makeStore()
        #expect(store.state.hrSource == .none)
        #expect(store.state.heartRateBPM == 0)
        #expect(store.state.hrZone == 0)
    }

    // MARK: - Ride aggregate tracking (#171)

    @Test("heartRateUpdated accumulates into HR sample sum/count/max")
    func heartRateAccumulatesAggregates() async {
        let store = makeStore()
        await store.send(.heartRateUpdated(140)) {
            $0.heartRateBPM = 140
            $0.hrZone = 2
            $0.hrSampleCount = 1
            $0.hrSampleSum = 140
            $0.maxHeartRateBPM = 140
        }
        await store.send(.heartRateUpdated(160)) {
            $0.heartRateBPM = 160
            $0.hrZone = 3
            $0.hrSampleCount = 2
            $0.hrSampleSum = 300
            $0.maxHeartRateBPM = 160
        }
        // A drop below the running max doesn't move maxHeartRateBPM.
        await store.send(.heartRateUpdated(120)) {
            $0.heartRateBPM = 120
            $0.hrZone = 1
            $0.hrSampleCount = 3
            $0.hrSampleSum = 420
            $0.maxHeartRateBPM = 160
        }
    }

    @Test("Zero bpm does not count toward the HR average")
    func zeroBPMDoesNotAccumulate() async {
        let store = makeStore()
        await store.send(.heartRateUpdated(0)) {
            $0.heartRateBPM = 0
            // Karvonen classifies a 0 bpm reading as zone 1 (intensity < 60% HRR) —
            // this test only cares that it doesn't move the aggregate fields.
            $0.hrZone = 1
        }
        #expect(store.state.hrSampleCount == 0)
        #expect(store.state.hrSampleSum == 0)
        #expect(store.state.maxHeartRateBPM == 0)
    }
}

// MARK: - Calibration suspension

/// PRD §8.9 suspends wheel auto-calibration during radar alerts. The parent derives
/// that from `isCalibrationSuspended` and forwards it on the transition
/// (`ActiveRideFeature.swift:294`).
///
/// The pause/resume half of that `||` is already asserted incidentally by the state
/// machine suite. The radar half was not reachable there: those stores start from
/// `ActiveRideFeature.State()`, whose `recordingState` defaults to `.idle`, so
/// suspension is already on before a target ever lands. These stores start recording.
@MainActor
@Suite("ActiveRideFeature — calibration suspension")
struct ActiveRideFeatureCalibrationSuspensionTests {

    private static func target(
        _ threatLevel: RadarTarget.ThreatLevel, slot: Int = 0
    ) -> RadarTarget {
        // Receding (negative velocity): this suite varies threatLevel to drive
        // isCalibrationSuspended, a concern independent of AlertLevel — pinning
        // velocity negative keeps every fixture here at AlertLevel.clear so these
        // tests don't also pick up unasserted alert-escalation state changes.
        RadarTarget(
            id: VariaRadarClient.vehicleSlotIDs[slot],
            relativeVelocityMPS: -8,
            rangeMetres: 40,
            threatLevel: threatLevel
        )
    }

    /// A clean fix one second apart from its predecessor at 10 m/s — inside the
    /// accuracy, moving-speed and gap gates, so it opens and holds the GPS gate.
    private static func fix(at second: TimeInterval) -> LocationUpdate {
        LocationUpdate(
            coordinate: Coordinate(latitude: 43.0731, longitude: -89.4012),
            altitude: 280,
            speed: 10,
            horizontalAccuracy: 5,
            heading: 192,
            timestamp: testDate.addingTimeInterval(second)
        )
    }

    private func makeStore() -> TestStoreOf<ActiveRideFeature> {
        TestStore(initialState: ActiveRideFeature.State(recordingState: .active)) {
            ActiveRideFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.date = .constant(testDate)
            $0.hapticsClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.locationClient = .testValue
            $0.bleCSCClient = .testValue
        }
    }

    @Test("A radar target above all-clear suspends calibration mid-ride")
    func radarAlertSuspendsCalibration() async {
        let store = makeStore()
        let targets = [Self.target(.danger)]

        await store.send(.radarTargetsUpdated(targets)) {
            $0.radarTargets = targets
            $0.vehiclePassTracking = [VariaRadarClient.vehicleSlotIDs[0]: singleSighting(mps: -8, alertLevel: .clear)]
        }
        await store.receive(\.calibration.suspensionChanged) {
            $0.calibration.isSuspended = true
        }
    }

    @Test("Returning to all-clear resumes calibration")
    func allClearResumesCalibration() async {
        let store = makeStore()
        let approaching = [Self.target(.warning)]

        await store.send(.radarTargetsUpdated(approaching)) {
            $0.radarTargets = approaching
            $0.vehiclePassTracking = [VariaRadarClient.vehicleSlotIDs[0]: singleSighting(mps: -8, alertLevel: .clear)]
        }
        await store.receive(\.calibration.suspensionChanged) {
            $0.calibration.isSuspended = true
        }

        // The vehicle going missing this tick doesn't change vehiclePassTracking —
        // fixed `.constant(testDate)` clock, so VehiclePassDetector's disappearance
        // grace period never elapses; the record is left tracked untouched pending
        // a reappearance or an explicit radar reset.
        await store.send(.radarTargetsUpdated([])) {
            $0.radarTargets = []
        }
        await store.receive(\.calibration.suspensionChanged) {
            $0.calibration.isSuspended = false
        }
    }

    @Test("Suspension is forwarded on the transition, not on every radar update")
    func suspensionForwardedOnlyOnTransition() async {
        let store = makeStore()
        let approaching = [Self.target(.warning)]

        await store.send(.radarTargetsUpdated(approaching)) {
            $0.radarTargets = approaching
            $0.vehiclePassTracking = [VariaRadarClient.vehicleSlotIDs[0]: singleSighting(mps: -8, alertLevel: .clear)]
        }
        await store.receive(\.calibration.suspensionChanged) {
            $0.calibration.isSuspended = true
        }

        // Radar notifies continuously. The threat escalating, or the vehicle closing,
        // must not re-send a flag that has not changed — the whole point of routing
        // this through `.onChange` rather than the target handler itself.
        let closing = [Self.target(.danger)]
        await store.send(.radarTargetsUpdated(closing)) {
            $0.radarTargets = closing
            // Same tracked vehicle (same slot id), not a new or disappeared one — a
            // second closing-velocity sample is folded into its existing record.
            $0.vehiclePassTracking = [
                VariaRadarClient.vehicleSlotIDs[0]: VehicleTrackingRecord(
                    firstSeenAt: testDate, lastSeenAt: testDate,
                    sampleCount: 2, positiveSampleCount: 0, positiveSampleSum: 0,
                    lastKnownCoordinate: nil, lastRiderSpeedMPS: 0, lastAlertLevel: .clear
                )
            ]
        }
        // No second .calibration(.suspensionChanged) fires — an unasserted receive
        // fails the test.
    }

    @Test("A radar alert pauses the window; clearing it resumes from the preserved totals")
    func radarAlertPausesAndResumesTheWindow() async {
        let store = makeStore()

        // Open both gates: the speed sensor is delivering, and a first clean fix
        // seeds the integration interval.
        await store.send(.calibration(.bleConnectionChanged(.active))) {
            $0.calibration.isSensorActive = true
        }
        await store.send(.calibration(.locationUpdated(Self.fix(at: 0)))) {
            $0.calibration.isGPSUsable = true
            $0.calibration.lastFixTimestamp = Self.fix(at: 0).timestamp
        }

        // One second of riding: 10 m of GPS distance against 5 wheel revolutions.
        await store.send(.calibration(.locationUpdated(Self.fix(at: 1)))) {
            $0.calibration.gpsMeters = 10
            $0.calibration.lastFixTimestamp = Self.fix(at: 1).timestamp
        }
        await store.send(.calibration(.wheelRevolutionsReceived(5))) {
            $0.calibration.revolutions = 5
        }

        let targets = [Self.target(.danger)]
        await store.send(.radarTargetsUpdated(targets)) {
            $0.radarTargets = targets
            $0.vehiclePassTracking = [VariaRadarClient.vehicleSlotIDs[0]: singleSighting(mps: -8, alertLevel: .clear)]
        }
        await store.receive(\.calibration.suspensionChanged) {
            $0.calibration.isSuspended = true
        }

        // Both accumulators freeze together — suppressing only one would manufacture
        // exactly the discrepancy this feature exists to detect. Only the fix
        // timestamp advances, which is what stops the resumed window integrating
        // across the alert.
        await store.send(.calibration(.locationUpdated(Self.fix(at: 2)))) {
            $0.calibration.lastFixTimestamp = Self.fix(at: 2).timestamp
        }
        await store.send(.calibration(.wheelRevolutionsReceived(5)))

        // Fixed clock — the disappearance grace period never elapses, so this
        // doesn't touch vehiclePassTracking; the record stays as tracked above.
        await store.send(.radarTargetsUpdated([])) {
            $0.radarTargets = []
        }
        await store.receive(\.calibration.suspensionChanged) {
            $0.calibration.isSuspended = false
        }

        // The road clears and the window carries on from where it stopped rather than
        // starting over: a rider in traffic would otherwise never complete one, and
        // that is exactly the rider who uses radar most (PRD §8.9).
        await store.send(.calibration(.locationUpdated(Self.fix(at: 3)))) {
            $0.calibration.gpsMeters = 20
            $0.calibration.lastFixTimestamp = Self.fix(at: 3).timestamp
        }
        await store.send(.calibration(.wheelRevolutionsReceived(5))) {
            $0.calibration.revolutions = 10
        }
    }
}

// MARK: - Shared CSC peripheral

/// One combo sensor assigned Both holds the Speed and Cadence roles at once
/// (BLE.md §5.0). Nothing at the feature layer correlates them — `SpeedFeature` and
/// `CadenceFeature` watch separate `connectionState(role:)` streams and never learn
/// they are watching the same device — so a single unplug reaches the ride as two
/// role-scoped events. These tests pin what that produces today.
@MainActor
@Suite("ActiveRideFeature — shared CSC peripheral")
struct ActiveRideFeatureSharedPeripheralTests {

    /// Mid-ride on one combo sensor: BLE speed on screen with a GPS shadow behind it,
    /// a live cadence reading, and a calibration window part-accumulated with one
    /// confirming measurement already banked.
    private static var midRide: ActiveRideFeature.State {
        var state = ActiveRideFeature.State(recordingState: .active)
        state.speed = SpeedFeature.State(
            speedMPS: 6.0,
            activeSpeedSource: .bleWheel,
            latestGPSSpeedMPS: 5.0,
            pairedSensorName: "Wahoo SPEED"
        )
        state.cadence = CadenceFeature.State(cadenceRPM: 82)
        state.calibration.isSensorActive = true
        state.calibration.isGPSUsable = true
        state.calibration.gpsMeters = 400
        state.calibration.revolutions = 195
        state.calibration.lastFixTimestamp = testDate
        state.calibration.pendingOverReading = true
        state.calibration.pendingMeasurements = [2051]
        return state
    }

    private func makeStore(clock: TestClock<Duration>) -> TestStoreOf<ActiveRideFeature> {
        TestStore(initialState: Self.midRide) {
            ActiveRideFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date = .constant(testDate)
            $0.hapticsClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.locationClient = .testValue
            $0.bleCSCClient = .testValue
        }
    }

    @Test("A combo sensor disconnecting fires speed fallback and cadence \"--\" together")
    func comboDisconnectFiresBothConsequences() async {
        let clock = TestClock()
        let store = makeStore(clock: clock)

        await store.send(.speed(.bleConnectionChanged(.disconnected))) {
            $0.speed.connectionState = .disconnected
            $0.speed.speedMPS = 5.0
            $0.speed.activeSpeedSource = .gps
            $0.speed.sourceSwitchBanner =
                SpeedFeature.gpsFallbackBannerText(sensorName: "Wahoo SPEED")
        }
        await store.send(.cadence(.bleConnectionChanged(.disconnected))) {
            $0.cadence.connectionState = .disconnected
            $0.cadence.cadenceRPM = nil
        }

        await clock.advance(by: SpeedFeature.bannerDismissDelay)
        await store.receive(\.speed.bannerDismissed) {
            $0.speed.sourceSwitchBanner = nil
        }

        // Cadence cleared on the spot and had no timer to fire: the 10 s grace window
        // guards a *reconnect*, and there is no fallback source to switch to
        // (BLE.md §6.2). Nothing arrives here — an unasserted receive fails the test.
        await clock.advance(by: CadenceFeature.reconnectGraceDelay)
    }

    @Test("One banner, not two, across a shared disconnect")
    func sharedDisconnectArmsASingleBanner() async {
        let clock = TestClock()
        let store = makeStore(clock: clock)

        await store.send(.speed(.bleConnectionChanged(.disconnected))) {
            $0.speed.connectionState = .disconnected
            $0.speed.speedMPS = 5.0
            $0.speed.activeSpeedSource = .gps
            $0.speed.sourceSwitchBanner =
                SpeedFeature.gpsFallbackBannerText(sensorName: "Wahoo SPEED")
        }
        await store.send(.cadence(.bleConnectionChanged(.disconnected))) {
            $0.cadence.connectionState = .disconnected
            $0.cadence.cadenceRPM = nil
        }
        await store.send(.calibration(.bleConnectionChanged(.disconnected))) {
            $0.calibration.isSensorActive = false
            $0.calibration.gpsMeters = 0
            $0.calibration.revolutions = 0
            $0.calibration.lastFixTimestamp = nil
            $0.calibration.pendingOverReading = nil
            $0.calibration.pendingMeasurements = []
        }

        // All three children reacted, and exactly one banner is armed —
        // `RideDashboardView.activeBanner` resolves the slot to a single capsule, so
        // a second armed banner would be silently dropped rather than stacked.
        //
        // Shipping behaviour, not the spec's: BLE.md §6.2 asks for one *combined*
        // notice, "Speed sensor disconnected — using GPS speed; cadence unavailable."
        // Cadence has no banner state at all today, and neither feature knows the two
        // roles share a peripheral. Tracked separately; asserted here so the gap is
        // visible at the assertion rather than only in a tracker.
        #expect(store.state.speed.sourceSwitchBanner != nil)
        #expect(store.state.calibration.banner == nil)

        await clock.advance(by: SpeedFeature.bannerDismissDelay)
        await store.receive(\.speed.bannerDismissed) {
            $0.speed.sourceSwitchBanner = nil
        }
    }

    @Test("A combo sensor disconnecting also voids the calibration window")
    func sharedDisconnectVoidsTheCalibrationWindow() async {
        let store = makeStore(clock: TestClock())

        // The speed role leaving `.active` discards the window outright, streak and
        // all — unlike a suspension, which pauses both accumulators together. A
        // reconnect gap loses revolutions that GPS kept counting through, and the
        // calculator will never replay them, so the window would read long (PRD §8.9).
        await store.send(.calibration(.bleConnectionChanged(.disconnected))) {
            $0.calibration.isSensorActive = false
            $0.calibration.gpsMeters = 0
            $0.calibration.revolutions = 0
            $0.calibration.lastFixTimestamp = nil
            $0.calibration.pendingOverReading = nil
            $0.calibration.pendingMeasurements = []
        }
    }
}

@MainActor
@Suite("ActiveRideFeature — units")
struct ActiveRideFeatureUnitsTests {

    /// Quarantines `AppPreferences` in its own in-memory storage, same as
    /// `ActiveRideFeatureStateMachineTests` — otherwise `state.unitSystem` would
    /// read whatever `app-preferences.json` happens to exist on the machine
    /// running the suite. `preferredUnit` is seeded inside the dependency scope
    /// so the `@SharedReader` in `ActiveRideFeature.State` resolves against it.
    private func makeStore(preferredUnit: UnitSystem) -> TestStoreOf<ActiveRideFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.preferredUnit = preferredUnit }
            return TestStore(initialState: ActiveRideFeature.State()) {
                ActiveRideFeature()
            } withDependencies: {
                $0.continuousClock = TestClock()
                $0.hapticsClient = .testValue
                $0.variaRadarClient = .testValue
                $0.bleHRClient = .testValue
                $0.locationClient = .testValue
                $0.defaultFileStorage = storage
            }
        }
    }

    @Test("unitSystem reads through to AppPreferences.preferredUnit", arguments: [
        UnitSystem.metric, .imperial
    ])
    func unitSystemReflectsPreferredUnit(preferredUnit: UnitSystem) {
        let store = makeStore(preferredUnit: preferredUnit)
        #expect(store.state.unitSystem == preferredUnit)
    }

    /// The dashboard reads `state.unitSystem` off the same shared document
    /// `SettingsFeature` writes to (#8) — a Settings toggle mid-ride must not
    /// need a lifecycle action to be picked up here.
    @Test("A Settings unit change propagates without a lifecycle action")
    func unitSystemPropagatesLiveWithNoAction() {
        let storage = FileStorage.inMemory
        withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.preferredUnit = .metric }
            let store = TestStore(initialState: ActiveRideFeature.State()) {
                ActiveRideFeature()
            } withDependencies: {
                $0.continuousClock = TestClock()
                $0.hapticsClient = .testValue
                $0.variaRadarClient = .testValue
                $0.bleHRClient = .testValue
                $0.locationClient = .testValue
                $0.defaultFileStorage = storage
            }
            #expect(store.state.unitSystem == .metric)

            $preferences.withLock { $0.preferredUnit = .imperial }
            #expect(store.state.unitSystem == .imperial)
        }
    }
}

// MARK: - Vehicle pass persistence

/// #172 code review: `vehiclePassCount` must advance only once a pass event is
/// actually confirmed persisted, not the moment `VehiclePassDetector` detects one —
/// otherwise a save failure leaves the in-memory count permanently ahead of what's
/// really in the SwiftData store, with no later checkpoint able to correct it (unlike
/// distanceMeters/durationSeconds, which get fully resent every checkpoint).
@MainActor
@Suite("ActiveRideFeature — vehicle pass persistence")
struct ActiveRideFeatureVehiclePassPersistenceTests {
    private static let coordinate = Coordinate(latitude: 43.0731, longitude: -89.4012)

    private static func vehicle(mps: Double) -> RadarTarget {
        RadarTarget(id: VariaRadarClient.vehicleSlotIDs[0], relativeVelocityMPS: mps, rangeMetres: 40, threatLevel: .allClear)
    }

    private func makeStore(persistenceClient: PersistenceClient) -> TestStoreOf<ActiveRideFeature> {
        let store = TestStore(
            initialState: ActiveRideFeature.State(recordingState: .active, coordinate: Self.coordinate)
        ) {
            ActiveRideFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.date = .constant(testDate)
            $0.hapticsClient = .testValue
            $0.audioClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.locationClient = .testValue
            $0.persistenceClient = persistenceClient
        }
        // This suite is about vehiclePassCount specifically — the alert-escalation
        // haptic/audio wiring these ticks also trigger has its own coverage above.
        store.exhaustivity = .off
        return store
    }

    /// Drives one full overtake through the real reducer: two sightings 2s apart
    /// (satisfying the tracked-duration minimum), then a confirmation tick 2s past
    /// the last sighting (satisfying the disappearance grace period).
    private func sendOvertake(on store: TestStoreOf<ActiveRideFeature>) async {
        await store.send(.radarTargetsUpdated([Self.vehicle(mps: 8)]))
        store.dependencies.date.now = testDate.addingTimeInterval(2)
        await store.send(.radarTargetsUpdated([Self.vehicle(mps: 8)]))
        store.dependencies.date.now = testDate.addingTimeInterval(4)
        await store.send(.radarTargetsUpdated([]))
    }

    @Test("vehiclePassCount increments once appendVehiclePassEvents succeeds")
    func vehiclePassCountIncrementsOnConfirmedPersistence() async {
        let appended = LockIsolated<[VehiclePassEventDTO]>([])
        let store = makeStore(persistenceClient: .mock(onAppendVehiclePassEvents: { appended.setValue($0) }))

        await sendOvertake(on: store)
        await store.receive(\.vehiclePassEventsPersisted)

        #expect(appended.value.count == 1)
        #expect(store.state.vehiclePassCount == 1)
    }

    @Test("A failed appendVehiclePassEvents write does not increment vehiclePassCount")
    func failedPersistenceDoesNotIncrementCount() async {
        struct WriteFailed: Error {}
        var persistenceClient = PersistenceClient.testValue
        persistenceClient.appendVehiclePassEvents = { _ in throw WriteFailed() }
        let store = makeStore(persistenceClient: persistenceClient)

        await sendOvertake(on: store)

        #expect(store.state.vehiclePassCount == 0)
    }

    @Test("vehiclePassCount flows into the checkpoint's RideSummaryUpdate")
    func vehiclePassCountReachesRideSummaryUpdate() async {
        let updatedSummary = LockIsolated<RideSummaryUpdate?>(nil)
        let store = makeStore(persistenceClient: .mock(
            onUpdateRideSummary: { updatedSummary.setValue($0) }
        ))

        await sendOvertake(on: store)
        await store.receive(\.vehiclePassEventsPersisted)
        #expect(store.state.vehiclePassCount == 1)

        await store.send(.pauseTapped)
        #expect(updatedSummary.value?.vehiclePassCount == 1)
    }
}
