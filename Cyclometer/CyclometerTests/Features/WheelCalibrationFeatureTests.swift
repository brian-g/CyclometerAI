import Testing
import Foundation
import ComposableArchitecture
@testable import Cyclometer

/// Serialized because these tests write `@Shared(.appPreferences)`. Each store gets
/// its own `FileStorage.inMemory`, but the shared reference behind the key is cached
/// process-wide, so a parallel test seeding the circumference can land between
/// another's commit and its assertion.
@MainActor
@Suite("WheelCalibrationFeature", .serialized)
struct WheelCalibrationFeatureTests {

    private static let start = Date(timeIntervalSince1970: 1_000_000)
    private static let storedMM = 2096

    /// Every store gets its own in-memory document. This feature *writes* the shared
    /// preferences, so without quarantine a test would persist into the developer's
    /// real `app-preferences.json` and leak into every other suite.
    private func makeStore(
        clock: any Clock<Duration> = TestClock(),
        bleCSCClient: BLECSCClient = .testValue,
        circumferenceMM: Int = storedMM,
        commitCount: Int = 0,
        confirmedWindows: Int = 0,
        pendingOverReading: Bool? = nil
    ) -> TestStoreOf<WheelCalibrationFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.wheelCircumferenceMM = circumferenceMM }
            var state = WheelCalibrationFeature.State()
            state.commitCount = commitCount
            state.confirmedWindows = confirmedWindows
            state.pendingOverReading = pendingOverReading
            return TestStore(initialState: state) {
                WheelCalibrationFeature()
            } withDependencies: {
                $0.defaultFileStorage = storage
                $0.continuousClock = clock
                $0.date = .constant(Self.start)
                $0.bleCSCClient = bleCSCClient
            }
        }
    }

    /// Opens the sensor gate. Suspension already starts open; GPS usability opens on
    /// the first clean fix.
    private func startRiding(
        _ store: TestStoreOf<WheelCalibrationFeature>
    ) async {
        await store.send(.bleConnectionChanged(.active)) { $0.isSensorActive = true }
    }

    /// Fixes needed to fill one window at the 10 m/s used throughout.
    private static var windowSeconds: Int { Int(WheelCalibration.windowThresholdMeters / 10) }

    /// Per-second revolution delta that makes one full window read `error` long
    /// (positive) or short (negative) against its GPS distance.
    private func revolutionRate(forError error: Double) -> Double {
        let gpsMeters = WheelCalibration.windowThresholdMeters
        let countedRevs = gpsMeters * (1 + error) * 1000 / Double(Self.storedMM)
        return countedRevs / Double(Self.windowSeconds)
    }

    /// Drives one full window non-exhaustively, returning the offset it ended at.
    private func driveWindow(
        _ store: TestStoreOf<WheelCalibrationFeature>,
        from startOffset: TimeInterval,
        error: Double
    ) async -> TimeInterval {
        let rate = revolutionRate(forError: error)
        var offset = startOffset
        await store.send(.locationUpdated(fix(at: offset)))
        for _ in 0..<Self.windowSeconds {
            await store.send(.wheelRevolutionsReceived(rate))
            offset += 1
            await store.send(.locationUpdated(fix(at: offset)))
        }
        return offset
    }

    private func fix(
        at offset: TimeInterval,
        speed: Double = 10,
        accuracy: Double = 5
    ) -> LocationUpdate {
        LocationUpdate(
            coordinate: Coordinate(latitude: 47.6, longitude: -122.3),
            altitude: 30,
            speed: speed,
            horizontalAccuracy: accuracy,
            heading: 90,
            timestamp: Self.start.addingTimeInterval(offset)
        )
    }

    /// Rides `seconds` of 1 Hz fixes at 10 m/s (10 m each) with a matching revolution
    /// delta per second, and returns the offset it finished at.
    ///
    /// The first fix only seeds the interval and contributes no distance, so `seconds`
    /// fixes yield `seconds × 10` metres.
    private func rideWindow(
        _ store: TestStoreOf<WheelCalibrationFeature>,
        from startOffset: TimeInterval,
        seconds: Int,
        revolutionsPerSecond: Double
    ) async -> TimeInterval {
        var offset = startOffset
        await store.send(.locationUpdated(fix(at: offset))) {
            $0.isGPSUsable = true
            $0.lastFixTimestamp = Self.start.addingTimeInterval(offset)
        }
        for _ in 0..<seconds {
            await store.send(.wheelRevolutionsReceived(revolutionsPerSecond)) {
                $0.revolutions += revolutionsPerSecond
            }
            offset += 1
            await store.send(.locationUpdated(fix(at: offset))) {
                $0.gpsMeters += 10
                $0.lastFixTimestamp = Self.start.addingTimeInterval(offset)
            }
        }
        return offset
    }

    // MARK: Subscriptions

    @Test("Start listening subscribes to the revolution and speed-connection streams")
    func startListeningSubscribes() async {
        let (revStream, revContinuation) = AsyncStream<Double>.makeStream()
        let (connStream, connContinuation) = AsyncStream<BLECSCClient.ConnectionState>.makeStream()
        var ble = BLECSCClient.testValue
        ble.wheelRevolutions = { revStream }
        ble.connectionState = { _ in connStream }

        let store = makeStore(bleCSCClient: ble)
        await store.send(.startListening)

        connContinuation.yield(.active)
        await store.receive(\.bleConnectionChanged) {
            $0.isSensorActive = true
        }
        // Gated: GPS has not reported a usable fix yet, so revolutions are ignored.
        revContinuation.yield(3)
        await store.receive(\.wheelRevolutionsReceived)

        revContinuation.finish()
        connContinuation.finish()
        await store.finish()
    }

    // MARK: Accumulation gates

    @Test("Nothing accumulates while the speed sensor is not active (PRD §8.9)")
    func noAccumulationWithoutSensor() async {
        let store = makeStore()

        // A full window of perfectly good GPS, with no BLE sensor connected.
        await store.send(.locationUpdated(fix(at: 0))) {
            $0.isGPSUsable = true
            $0.lastFixTimestamp = Self.start
        }
        for i in 1...160 {
            await store.send(.locationUpdated(fix(at: TimeInterval(i)))) {
                $0.lastFixTimestamp = Self.start.addingTimeInterval(TimeInterval(i))
            }
        }
        #expect(store.state.gpsMeters == 0)
        #expect(store.state.commitCount == 0)
    }

    @Test("A fix worse than 10 m accuracy pauses the window without discarding it")
    func poorAccuracyPauses() async {
        let store = makeStore()
        await startRiding(store)

        _ = await rideWindow(store, from: 0, seconds: 5, revolutionsPerSecond: 4.77)
        let metresBefore = store.state.gpsMeters
        let revsBefore = store.state.revolutions
        #expect(metresBefore == 50)

        await store.send(.locationUpdated(fix(at: 6, accuracy: 12))) {
            $0.isGPSUsable = false
            $0.lastFixTimestamp = nil
        }
        // Revolutions are dropped too — suppressing one accumulator alone would
        // manufacture the very discrepancy the feature looks for.
        await store.send(.wheelRevolutionsReceived(4.77))
        #expect(store.state.gpsMeters == metresBefore)
        #expect(store.state.revolutions == revsBefore)

        // Recovery re-seeds the interval rather than integrating across the gap.
        await store.send(.locationUpdated(fix(at: 10))) {
            $0.isGPSUsable = true
            $0.lastFixTimestamp = Self.start.addingTimeInterval(10)
        }
        #expect(store.state.gpsMeters == metresBefore)
    }

    @Test("Suspension pauses both accumulators and preserves progress")
    func suspensionPauses() async {
        let store = makeStore()
        await startRiding(store)
        _ = await rideWindow(store, from: 0, seconds: 5, revolutionsPerSecond: 4.77)
        let metresBefore = store.state.gpsMeters
        let revsBefore = store.state.revolutions

        await store.send(.suspensionChanged(true)) { $0.isSuspended = true }
        await store.send(.wheelRevolutionsReceived(4.77))
        await store.send(.locationUpdated(fix(at: 6))) {
            $0.lastFixTimestamp = Self.start.addingTimeInterval(6)
        }
        #expect(store.state.gpsMeters == metresBefore)
        #expect(store.state.revolutions == revsBefore)

        await store.send(.suspensionChanged(false)) { $0.isSuspended = false }
        await store.send(.locationUpdated(fix(at: 7))) {
            $0.gpsMeters += 10
            $0.lastFixTimestamp = Self.start.addingTimeInterval(7)
        }
        #expect(store.state.gpsMeters == metresBefore + 10)

    }

    @Test("A GPS gap over 3 seconds pauses the window")
    func gpsGapPauses() async {
        let store = makeStore()
        await startRiding(store)
        _ = await rideWindow(store, from: 0, seconds: 3, revolutionsPerSecond: 4.77)
        let metresBefore = store.state.gpsMeters

        await store.send(.locationUpdated(fix(at: 12))) {
            $0.isGPSUsable = false
            $0.lastFixTimestamp = nil
        }
        #expect(store.state.gpsMeters == metresBefore)
    }

    @Test("A stationary or invalid fix pauses the window")
    func stationaryFixPauses() async {
        let store = makeStore()
        await startRiding(store)
        _ = await rideWindow(store, from: 0, seconds: 3, revolutionsPerSecond: 4.77)
        let metresBefore = store.state.gpsMeters

        await store.send(.locationUpdated(fix(at: 4, speed: 0.5))) {
            $0.isGPSUsable = false
            $0.lastFixTimestamp = nil
        }
        // Already paused, so the invalid-speed sentinel changes nothing further.
        await store.send(.locationUpdated(fix(at: 5, speed: -1)))
        #expect(store.state.gpsMeters == metresBefore)
    }

    @Test("Losing the speed sensor discards the window outright")
    func sensorLossDiscardsWindow() async {
        let store = makeStore()
        await startRiding(store)
        _ = await rideWindow(store, from: 0, seconds: 5, revolutionsPerSecond: 4.77)
        #expect(store.state.gpsMeters == 50)

        // A reconnect gap loses revolutions GPS kept counting through, so unlike a
        // suspension the window cannot be salvaged.
        await store.send(.bleConnectionChanged(.reconnecting)) {
            $0.isSensorActive = false
            $0.gpsMeters = 0
            $0.revolutions = 0
            $0.lastFixTimestamp = nil
        }
    }

    // MARK: Triggering

    @Test("One qualifying window is not enough — a correction needs two in a row")
    func singleWindowDoesNotCommit() async {
        let store = makeStore()
        store.exhaustivity = .off
        await startRiding(store)

        // 6% over-read — comfortably clear of the 2% threshold.
        _ = await driveWindow(store, from: 0, error: 0.06)

        #expect(store.state.commitCount == 0)
        #expect(store.state.confirmedWindows == 1)
        #expect(store.state.pendingOverReading == true)
        // Measurements cleared, streak kept.
        #expect(store.state.gpsMeters == 0)
        #expect(store.state.revolutions == 0)
        #expect(store.state.preferences.wheelCircumferenceMM == Self.storedMM)
    }

    @Test("Two consecutive agreeing windows commit, persist, push and banner")
    func twoWindowsCommit() async throws {
        let pushed = LockIsolated<[Int]>([])
        var ble = BLECSCClient.testValue
        ble.setWheelCircumference = { mm in pushed.withValue { $0.append(mm) } }

        // Seeded one window into the streak so only the confirming window has to be
        // driven here; `singleWindowDoesNotCommit` covers the first one.
        let store = makeStore(
            clock: ImmediateClock(),
            bleCSCClient: ble,
            confirmedWindows: WheelCalibration.confirmationWindows - 1,
            pendingOverReading: true
        )
        store.exhaustivity = .off
        await startRiding(store)

        // 6% over-read, driven to one fix short of closing the window.
        let rate = revolutionRate(forError: 0.06)
        await store.send(.locationUpdated(fix(at: 0)))
        for i in 1..<Self.windowSeconds {
            await store.send(.wheelRevolutionsReceived(rate))
            await store.send(.locationUpdated(fix(at: TimeInterval(i))))
        }
        #expect(store.state.commitCount == 0)

        // Exhaustive from here: the committing send emits the banner-dismissal
        // effect, and a non-exhaustive `send` would sweep that action away before it
        // could be asserted.
        let expected = Int((Double(Self.storedMM) / 1.06).rounded())
        let closingFix = TimeInterval(Self.windowSeconds)
        store.exhaustivity = .on
        await store.send(.wheelRevolutionsReceived(rate)) { $0.revolutions += rate }
        await store.send(.locationUpdated(fix(at: closingFix))) {
            $0.$preferences.withLock { $0.wheelCircumferenceMM = expected }
            $0.commitCount = 1
            $0.lastCalibrationAt = Self.start
            $0.banner = WheelCalibration.bannerText(mm: expected)
            // Window cleared, streak cleared — but the fix that closed the window
            // still seeds the next interval, so no riding is lost between windows.
            $0.gpsMeters = 0
            $0.revolutions = 0
            $0.confirmedWindows = 0
            $0.pendingOverReading = nil
            $0.lastFixTimestamp = Self.start.addingTimeInterval(closingFix)
        }
        await store.receive(\.bannerDismissed) { $0.banner = nil }

        await store.finish(timeout: .seconds(1))
        #expect(pushed.value == [expected])
    }

    @Test("A window disagreeing with its predecessor restarts the streak")
    func signFlipResetsConfirmation() async {
        let store = makeStore()
        store.exhaustivity = .off
        await startRiding(store)

        var offset: TimeInterval = 0
        for error in [0.06, -0.06] {          // reads long, then reads short
            offset = await driveWindow(store, from: offset, error: error) + 1
        }

        #expect(store.state.commitCount == 0)
        #expect(store.state.confirmedWindows == 1)
        #expect(store.state.pendingOverReading == false)
    }

    @Test("The per-ride commit cap refuses a fourth correction")
    func perRideCapRefuses() async {
        // Seeded one window short of confirmation, so the window driven below is the
        // one that would otherwise commit.
        let store = makeStore(
            commitCount: WheelCalibration.maxCommitsPerRide,
            confirmedWindows: WheelCalibration.confirmationWindows - 1,
            pendingOverReading: true
        )
        store.exhaustivity = .off
        await startRiding(store)

        _ = await driveWindow(store, from: 0, error: 0.06)

        #expect(store.state.commitCount == WheelCalibration.maxCommitsPerRide)
        #expect(store.state.preferences.wheelCircumferenceMM == Self.storedMM)
        #expect(store.state.banner == nil)
    }

    @Test("A window that agrees with the stored circumference leaves it alone")
    func accurateWindowDoesNothing() async {
        let store = makeStore()
        store.exhaustivity = .off
        await startRiding(store)

        _ = await driveWindow(store, from: 0, error: 0)

        #expect(store.state.commitCount == 0)
        #expect(store.state.confirmedWindows == 0)
        #expect(store.state.preferences.wheelCircumferenceMM == Self.storedMM)
    }
}
