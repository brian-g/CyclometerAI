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
@MainActor
@Suite("ActiveRideFeature — frozen wheel sensor and auto-pause (#623)")
struct FrozenWheelAutoPauseTests {

    /// One second of a ride: the wheel frame `CSCCalculator` emitted (nil when it emitted none),
    /// and the GPS fix that arrived (nil when none did).
    typealias Second = (wheel: Double?, gps: (speed: Double, accuracy: Double)?)

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
    private func makeStore() -> TestStoreOf<ActiveRideFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.isAutoPauseEnabled = true }
            var state = ActiveRideFeature.State(recordingState: .active)
            state.speed = SpeedFeature.State(
                speedMPS: 3.0,
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
}
