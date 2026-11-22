import ComposableArchitecture
import Foundation
import Testing
@testable import Cyclometer

/// Matches the fixed clock the other `ActiveRideFeature` suites run on.
private let testDate = Date(timeIntervalSince1970: 1_000_000)

/// #623: after a stop, a Wahoo SPEED sensor can stop counting revolutions for 5–9 s once the
/// wheel turns again. Its frames read 0 while GPS has the rider moving, and on ride 2026-11-21
/// those seconds auto-paused the ride four times, each just as the rider pulled away. A good,
/// fresh GPS fix at `movingSpeedMPS` keeps such a second off the auto-pause count; the wheel
/// still owns the displayed speed, distance and Avg.
///
/// #643 is the same fault after a real stop: the ride stayed paused while the frozen wheel read 0
/// and the rider rode away. Two such fixes in a row now resume it.
@MainActor
@Suite("ActiveRideFeature — frozen wheel sensor, auto-pause and auto-resume (#623, #643)")
struct FrozenWheelAutoPauseTests {

    /// One second of a ride: the wheel frame `CSCCalculator` emitted (nil when it emitted none),
    /// and the GPS fix that arrived (nil when none did).
    typealias Second = (wheel: Double?, gps: (speed: Double, accuracy: Double)?)

    enum Pause { case auto, manual }

    /// Ride 2026-11-21, 12:03:13–12:03:26, one entry a second. Wheel frames are the log's. The
    /// log has no Doppler line, so GPS speed is the GPX's positional speed held one second back,
    /// which puts it through 2.0 m/s at :23, where the log's `calibration gps gate open` did.
    /// Accuracy was 2.1 m throughout. The rider stops at :15 and pulls away around :20; the
    /// wheel reads 0 until :26. It auto-paused at :24.
    private static let ride1203: [Second] = [
        (2.67, (1.1, 2.1)), (nil, (0.3, 2.1)), (0.15, (0.2, 2.1)), (nil, (0.2, 2.1)),
        (nil, (0.1, 2.1)), (0, (0.1, 2.1)), (0, (0.1, 2.1)), (0, (0.1, 2.1)),
        (0, (1.1, 2.1)), (0, (1.2, 2.1)), (0, (2.0, 2.1)), (0, (2.4, 2.1)),
        (nil, (3.1, 2.1)), (2.59, (3.1, 2.1)),
    ]

    private let now = LockIsolated(testDate)

    /// The state is built inside the in-memory storage scope, so its preferences read the
    /// `isAutoPauseEnabled` set here rather than whatever storage the host resolves.
    ///
    /// - Parameter pause: nil for a ride riding at 3 m/s; otherwise the ride is paused that way,
    ///   the wheel the source and reading 0.
    private func makeStore(
        pause: Pause? = nil, isResumeWhenMovingEnabled: Bool = false, isAutoPauseEnabled: Bool = true
    ) -> TestStoreOf<ActiveRideFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock {
                $0.isAutoPauseEnabled = isAutoPauseEnabled
                $0.isResumeWhenMovingEnabled = isResumeWhenMovingEnabled
            }
            var state = ActiveRideFeature.State(recordingState: pause == nil ? .active : .paused)
            state.isAutoPaused = pause == .auto
            state.speed = SpeedFeature.State(
                speedMPS: pause == nil ? 3.0 : 0,
                activeSpeedSource: .bleWheel,
                connectionState: .active,
                pairedSensorName: "Wahoo SPEED"
            )
            let store = TestStore(initialState: state) {
                ActiveRideFeature()
            } withDependencies: { [now] in
                $0.continuousClock = TestClock()
                $0.date = DateGenerator { now.value }
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

    /// Plays `seconds` one a second and returns the 1-based ticks that left the ride paused.
    /// Every fix carries `speedAccuracy`. `eachSecond` runs after every tick.
    @discardableResult
    private func replay(
        _ seconds: [Second], on store: TestStoreOf<ActiveRideFeature>, speedAccuracy: Double? = nil,
        eachSecond: (TestStoreOf<ActiveRideFeature>) -> Void = { _ in }
    ) async -> [Int] {
        var pausedTicks: [Int] = []
        for (index, second) in seconds.enumerated() {
            now.withValue { $0.addTimeInterval(1) }
            if let wheel = second.wheel { await store.send(.speed(.bleSpeedReceived(wheel))) }
            if let gps = second.gps {
                await store.send(.locationUpdated(LocationUpdate(
                    coordinate: Coordinate(latitude: 43.0, longitude: -89.0), altitude: 280,
                    speed: gps.speed, speedAccuracy: speedAccuracy, horizontalAccuracy: gps.accuracy,
                    heading: 0, timestamp: now.value
                )))
            }
            await store.send(.elapsedTick)
            // The tick only sends `.autoPauseTriggered`; let it land before reading the state.
            await store.skipReceivedActions(strict: false)
            eachSecond(store)
            if store.state.recordingState == .paused { pausedTicks.append(index + 1) }
        }
        return pausedTicks
    }

    @Test("The 12:03 stop: the frozen wheel's zero doesn't auto-pause a rider GPS has moving")
    func ride1203DoesNotAutoPause() async {
        let store = makeStore()
        var held = 3.0
        var distance = 0.0
        let paused = await replay(Self.ride1203, on: store) { store in
            #expect(store.state.zeroSpeedSeconds < ActiveRideFeature.autoPauseZeroSpeedSeconds)
        }
        #expect(paused.isEmpty)
        #expect(!store.state.isAutoPaused)

        // The wheel still owns what the rider sees and what the ride records.
        for second in Self.ride1203 {
            if let wheel = second.wheel { held = wheel }
            if held > ActiveRideFeature.stationarySpeedMPS { distance += held }
        }
        #expect(store.state.speed.activeSpeedSource == .bleWheel)
        #expect(store.state.speed.speedMPS == 2.59)
        #expect(abs(store.state.distanceMeters - distance) < 1e-9)
    }

    @Test(
        "A wheel reading 0 still auto-pauses at the threshold when GPS can't show the rider moving",
        arguments: [
            ("GPS stationary", (speed: 0.04, accuracy: 2.0) as (speed: Double, accuracy: Double)?),
            ("GPS just under moving speed", (speed: 0.99, accuracy: 2.0)),
            ("GPS moving, poor accuracy", (speed: 3.0, accuracy: GPSFixFilter.maxHorizontalAccuracy + 0.1)),
            ("GPS moving, invalid accuracy", (speed: 3.0, accuracy: -1)),
            ("no fix", nil),
        ]
    )
    func stoppedWheelAutoPauses(_ label: String, gps: (speed: Double, accuracy: Double)?) async {
        let store = makeStore()
        let threshold = ActiveRideFeature.autoPauseZeroSpeedSeconds
        let seconds = [Second](repeating: (0, gps), count: threshold)
        let paused = await replay(seconds, on: store)
        #expect(paused.first == threshold, "\(label)")
    }

    @Test("A moving GPS speed whose speedAccuracy is past MaxSpeedGate's ceiling doesn't hold the count")
    func untrustworthyGPSSpeedAutoPauses() async {
        let store = makeStore()
        let threshold = ActiveRideFeature.autoPauseZeroSpeedSeconds
        let seconds = [Second](repeating: (0, (3.0, 2.0)), count: threshold)
        let paused = await replay(seconds, on: store, speedAccuracy: MaxSpeedGate.maxGPSSpeedAccuracyMPS + 0.1)
        #expect(paused.first == threshold)
    }

    @Test("A fix stamped after now, the wall clock having stepped back, doesn't veto the wheel's zero")
    func clockStepBackStopsVetoing() async {
        let store = makeStore()
        let threshold = ActiveRideFeature.autoPauseZeroSpeedSeconds
        let seconds: [Second] = [(0, (5.0, 2.0))] + [Second](repeating: (0, nil), count: threshold)
        var hasStepped = false
        let paused = await replay(seconds, on: store) { _ in
            guard !hasStepped else { return }
            hasStepped = true
            now.withValue { $0.addTimeInterval(-60) }
        }
        // The fix's own second doesn't count; every one after the step does.
        #expect(paused.first == threshold + 1)
    }

    @Test("Once fixes stop, a held moving GPS speed vetoes the wheel's zero for movingGPSFixMaxAge at most")
    func staleFixStopsVetoing() async {
        let store = makeStore()
        // One moving fix, then iOS sends no more (#383): the speed is held, the fix ages out.
        let threshold = ActiveRideFeature.autoPauseZeroSpeedSeconds
        let held = Int(ActiveRideFeature.movingGPSFixMaxAge)
        let seconds: [Second] = [(0, (5.0, 2.0))]
            + [Second](repeating: (0, nil), count: threshold + held)
        let paused = await replay(seconds, on: store)
        #expect(store.state.speed.latestGPSSpeedMPS == 5.0)
        // The fix's own second and the `held` after it don't count; every one after does.
        #expect(paused.first == threshold + held + 1)
    }

    @Test("A wheel that stays at 0 while GPS moves, as on a bike rack, auto-pauses once the veto is spent")
    func bikeOnARackAutoPauses() async {
        let store = makeStore()
        let threshold = ActiveRideFeature.autoPauseZeroSpeedSeconds
        let cap = ActiveRideFeature.maxGPSMovingVetoSeconds
        // Driving with the ride running: the sensor keeps sending 0, every fix is good and fast.
        let seconds = [Second](repeating: (0, (20.0, 3.0)), count: cap + threshold)
        let paused = await replay(seconds, on: store)
        #expect(paused.first == cap + threshold)
    }

    @Test("The veto cap is per freeze: a wheel reading moving between two freezes restores it")
    func wheelMovingRestoresTheVeto() async {
        let store = makeStore()
        let cap = ActiveRideFeature.maxGPSMovingVetoSeconds
        // Two freezes that together exceed the cap, each within it, split by one real reading.
        let freeze = [Second](repeating: (0, (3.0, 2.0)), count: cap - 1)
        let paused = await replay(freeze + [(3.0, (3.0, 2.0))] + freeze, on: store) { store in
            #expect(store.state.zeroSpeedSeconds == 0)
        }
        #expect(paused.isEmpty)
    }

    // MARK: - Auto-resume (#643)

    /// Ride 2026-11-21, 12:59:13–12:59:19, auto-paused since 12:58:27. Wheel frames are the log's: 0
    /// through :16, none at :17–18 (the sensor re-priming), 3.34 m/s at :19, where the ride resumed.
    /// The log has no Doppler line and, paused, the GPX has no points, so the GPS speeds are
    /// assumed, set to fit what the log does say: accuracy flapped about 10.7–11 m through the
    /// pause, the recording gate opened at 9.5 m at :14, and the calibration gate (Doppler
    /// ≥ 2.0 m/s, accuracy ≤ 10 m) opened at :15 and stayed open until :21.
    private static let ride1259: [Second] = [
        (0, (0.6, 10.8)), (0, (0.9, 9.5)), (0, (2.1, 9.5)), (0, (2.5, 9.5)),
        (nil, (2.8, 9.5)), (nil, (3.1, 9.5)), (3.34, (3.3, 9.5)),
    ]

    /// The first 1-based tick that left the ride riding, from `replay`'s paused ticks.
    private func firstActiveTick(_ paused: [Int], of count: Int) -> Int? {
        (1...count).first { !paused.contains($0) }
    }

    @Test("The 12:59 stop: two moving fixes resume the ride before the frozen wheel reads moving")
    func ride1259ResumesOnGPS() async {
        let store = makePausedStore()
        let paused = await replay(Self.ride1259, on: store)
        // :16, the second fix with the gate open; the wheel's first reading is tick 7, :19.
        #expect(firstActiveTick(paused, of: Self.ride1259.count) == 4)
        #expect(paused == [1, 2, 3])

        // The wheel still owns what the rider sees and what the ride records: no distance until it
        // reads moving, and once it does the veto the resume spent is back.
        #expect(store.state.speed.activeSpeedSource == .bleWheel)
        #expect(store.state.speed.speedMPS == 3.34)
        #expect(abs(store.state.distanceMeters - 3.34) < 1e-9)
        #expect(store.state.zeroSpeedSeconds == 0)
        #expect(store.state.gpsMovingVetoSeconds == 0)
    }

    @Test(
        "An auto-paused ride whose wheel reads 0 stays paused when GPS can't show the rider moving",
        arguments: [
            ("GPS stationary", (speed: 0.04, accuracy: 2.0) as (speed: Double, accuracy: Double)?),
            ("GPS just under moving speed", (speed: 0.99, accuracy: 2.0)),
            ("GPS moving, poor accuracy", (speed: 3.0, accuracy: GPSFixFilter.maxHorizontalAccuracy + 0.1)),
            ("GPS moving, invalid accuracy", (speed: 3.0, accuracy: -1)),
            ("no fix", nil),
        ]
    )
    func stoppedWheelStaysPaused(_ label: String, gps: (speed: Double, accuracy: Double)?) async {
        let store = makePausedStore()
        let seconds = [Second](repeating: (0, gps), count: 10)
        let paused = await replay(seconds, on: store)
        #expect(paused.count == seconds.count, "\(label)")
    }

    @Test("A moving GPS speed whose speedAccuracy is past MaxSpeedGate's ceiling doesn't resume")
    func untrustworthyGPSSpeedStaysPaused() async {
        let store = makePausedStore()
        let seconds = [Second](repeating: (0, (3.0, 2.0)), count: 10)
        let paused = await replay(seconds, on: store, speedAccuracy: MaxSpeedGate.maxGPSSpeedAccuracyMPS + 0.1)
        #expect(paused.count == seconds.count)
    }

    @Test("One moving fix at a time, between stopped ones or before fixes stop, doesn't resume")
    func loneMovingFixesStayPaused() async {
        let store = makePausedStore()
        // Ends on a moving fix, then iOS sends no more.
        let stray: [Second] = [(0, (0.04, 2.0)), (0, (3.0, 2.0))]
        let seconds = Array([[Second]](repeating: stray, count: 5).joined())
            + [Second](repeating: (0, nil), count: 5)
        let paused = await replay(seconds, on: store)
        #expect(paused.count == seconds.count)
    }

    @Test("A manual pause resumes on GPS only under Resume When Moving's own rules")
    func manualPauseFollowsResumeWhenMoving() async {
        let moving = [Second](repeating: (0, (3.0, 2.0)), count: 5)

        let off = makePausedStore(.manual)
        let pausedOff = await replay(moving, on: off)
        #expect(pausedOff.count == moving.count)

        // The wheel's 0 is the stop that arms it (#267).
        let on = makePausedStore(.manual, isResumeWhenMovingEnabled: true)
        let pausedOn = await replay(moving, on: on)
        #expect(firstActiveTick(pausedOn, of: moving.count) == 2)
    }

    @Test("A bike driven away on a rack resumes once, pauses again after the count, and stays paused")
    func bikeOnARackResumesOnce() async {
        let store = makePausedStore()
        let threshold = ActiveRideFeature.autoPauseZeroSpeedSeconds
        let resumeTick = ActiveRideFeature.gpsResumeFixCount
        // The sensor keeps sending 0; every fix is good and fast.
        let seconds = [Second](repeating: (0, (20.0, 3.0)), count: 60)
        let paused = await replay(seconds, on: store)
        // The resume spent the veto, so each tick from the resume counts toward auto-pause.
        let repauseTick = resumeTick + threshold - 1
        #expect(paused == Array(1..<resumeTick) + Array(repauseTick...seconds.count))
        #expect(store.state.distanceMeters == 0)
    }

    @Test("A Pause tapped while riding on stays paused once the bike stops, GPS a fix behind (#267)")
    func pauseTappedWhileRidingStaysPausedAtTheStop() async {
        let store = makePausedStore(.manual, isResumeWhenMovingEnabled: true)
        // Riding on after the tap, GPS agreeing, inside the grace; then the stop that arms the pause.
        let seconds = [Second](repeating: (3.0, (3.0, 2.0)), count: 5)
            + [(0, (1.5, 2.0))]
            + [Second](repeating: (0, (0.04, 2.0)), count: 5)
        let paused = await replay(seconds, on: store)
        #expect(paused.count == seconds.count)
    }

    @Test("Without auto-pause nothing would pause a GPS resume again, so GPS doesn't resume")
    func gpsResumeNeedsAutoPause() async {
        let store = makePausedStore(.manual, isResumeWhenMovingEnabled: true, isAutoPauseEnabled: false)
        let moving = [Second](repeating: (0, (3.0, 2.0)), count: 5)
        let paused = await replay(moving, on: store)
        #expect(paused.count == moving.count)
    }

    @Test("An auto-paused ride with the Finish alert up doesn't resume on GPS")
    func finishAlertBlocksGPSResume() async {
        let store = makePausedStore()
        await store.send(.finishTapped)
        let moving = [Second](repeating: (0, (3.0, 2.0)), count: 5)
        let paused = await replay(moving, on: store)
        #expect(paused.count == moving.count)
    }

    @Test("Two moving fixes with a gap between them aren't two in a row")
    func movingFixesAcrossAGapStayPaused() async {
        let store = makePausedStore()
        let gap = [Second](repeating: (0, nil), count: Int(ActiveRideFeature.movingGPSFixMaxAge))
        let seconds: [Second] = [(0, (3.0, 2.0))] + gap + [(0, (3.0, 2.0)), (0, (0.04, 2.0))]
        let paused = await replay(seconds, on: store)
        #expect(paused.count == seconds.count)
    }

    private func makePausedStore(
        _ pause: Pause = .auto, isResumeWhenMovingEnabled: Bool = false, isAutoPauseEnabled: Bool = true
    ) -> TestStoreOf<ActiveRideFeature> {
        makeStore(
            pause: pause, isResumeWhenMovingEnabled: isResumeWhenMovingEnabled, isAutoPauseEnabled: isAutoPauseEnabled
        )
    }
}
