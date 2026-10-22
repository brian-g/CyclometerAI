import Testing
import Foundation
import ComposableArchitecture
@testable import Cyclometer

@MainActor
@Suite("SpeedFeature")
struct SpeedFeatureTests {

    private static let testDate = Date(timeIntervalSince1970: 1_000_000)

    private func makeStore(
        initialState: SpeedFeature.State = SpeedFeature.State(),
        clock: TestClock<Duration> = TestClock(),
        bleCSCClient: BLECSCClient = .testValue,
        date: Date = Self.testDate,
        fileStorage: FileStorage? = nil
    ) -> TestStoreOf<SpeedFeature> {
        TestStore(initialState: initialState) {
            SpeedFeature()
        } withDependencies: {
            $0.date = .constant(date)
            $0.continuousClock = clock
            $0.bleCSCClient = bleCSCClient
            if let fileStorage { $0.defaultFileStorage = fileStorage }
        }
    }

    @Test("Valid GPS speed sets speedMPS, source, and appends a timestamped sample")
    func validGPSSpeed() async {
        let store = makeStore()

        await store.send(.gpsSpeedReceived(8.5)) {
            $0.speedMPS = 8.5
            $0.activeSpeedSource = .gps
            $0.latestGPSSpeedMPS = 8.5
            $0.speedSamples = [SpeedSample(time: Self.testDate, mps: 8.5)]
        }
    }

    @Test("Invalid GPS speed clears speedMPS and source")
    func invalidGPSSpeedClearsState() async {
        let store = makeStore(
            initialState: SpeedFeature.State(speedMPS: 8.5, activeSpeedSource: .gps)
        )

        await store.send(.gpsSpeedReceived(-1)) {
            $0.speedMPS = nil
            $0.activeSpeedSource = .none
        }
    }

    @Test("Start listening subscribes to BLE speed, connection-state, and sensor-name streams")
    func startListeningSubscribesToBLEStreams() async {
        let (speedStream, speedContinuation) = AsyncStream<Double>.makeStream()
        let (connStream, connContinuation) = AsyncStream<BLECSCClient.ConnectionState>.makeStream()
        let (nameStream, nameContinuation) = AsyncStream<String?>.makeStream()
        var ble = BLECSCClient.testValue
        ble.speed = { speedStream }
        ble.connectionState = { _ in connStream }
        ble.sensorName = { _ in nameStream }

        let clock = TestClock()
        let store = makeStore(clock: clock, bleCSCClient: ble)
        await store.send(.startListening)

        connContinuation.yield(.scanning)
        await store.receive(\.bleConnectionChanged) {
            $0.connectionState = .scanning
        }

        nameContinuation.yield("Wahoo RPM")
        await store.receive(\.bleSensorNameChanged) {
            $0.pairedSensorName = "Wahoo RPM"
        }

        speedContinuation.yield(3.5)
        await store.receive(\.bleSpeedReceived) {
            $0.speedMPS = 3.5
            $0.activeSpeedSource = .bleWheel
            $0.speedSamples = [SpeedSample(time: Self.testDate, mps: 3.5)]
        }

        speedContinuation.finish()
        connContinuation.finish()
        nameContinuation.finish()
        // The reading armed the stale-data watchdog, and nothing follows it.
        await clock.advance(by: SpeedFeature.staleDataWindow)
        await store.receive(\.bleFallbackTimedOut) {
            $0.speedMPS = nil
            $0.activeSpeedSource = .none
            $0.sourceSwitchBanner = SpeedFeature.gpsFallbackBannerText(sensorName: "Wahoo RPM")
            $0.lastFallbackBannerAt = Self.testDate
        }
        await clock.advance(by: SpeedFeature.bannerDismissDelay)
        await store.receive(\.bannerDismissed) {
            $0.sourceSwitchBanner = nil
        }
        await store.finish()
    }

    @Test("Start listening applies the persisted wheel circumference before scanning")
    func startListeningAppliesPersistedCircumference() async {
        // Ordering matters: the circumference must land before the first
        // measurement, so record the sequence rather than just the value.
        let calls = LockIsolated<[String]>([])
        var ble = BLECSCClient.testValue
        ble.setWheelCircumference = { mm in calls.withValue { $0.append("circumference:\(mm)") } }
        ble.startScanning = { calls.withValue { $0.append("scan") } }

        // Own in-memory storage so the seeded circumference cannot leak into (or
        // out of) other tests sharing the process-wide default.
        let storage = FileStorage.inMemory
        let store = withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.wheelCircumferenceMM = 2288 }
            return makeStore(bleCSCClient: ble, fileStorage: storage)
        }

        await store.send(.startListening)
        await store.finish()

        #expect(calls.value == ["circumference:2288", "scan"])
    }

    @Test("Samples older than the history window are pruned")
    func prunesSamplesOlderThanWindow() async {
        let start = Date(timeIntervalSince1970: 0)
        let stale = SpeedSample(time: start, mps: 5.0)                            // t=0
        let recent = SpeedSample(time: start.addingTimeInterval(1800), mps: 6.0)  // t=1800
        let now = start.addingTimeInterval(SpeedFeature.historyWindow + 1)        // t=3601

        let store = makeStore(
            initialState: SpeedFeature.State(speedSamples: [stale, recent]),
            date: now
        )

        await store.send(.gpsSpeedReceived(7.0)) {
            $0.speedMPS = 7.0
            $0.activeSpeedSource = .gps
            $0.latestGPSSpeedMPS = 7.0
            // stale (t=0) is now older than the window → pruned; recent + new stay.
            $0.speedSamples = [recent, SpeedSample(time: now, mps: 7.0)]
        }
    }

    @Test("Invalid GPS speed does not append to speed samples")
    func invalidSpeedSkipsHistory() async {
        let store = makeStore(
            initialState: SpeedFeature.State(
                speedMPS: 8.5,
                activeSpeedSource: .gps,
                speedSamples: [SpeedSample(time: Self.testDate, mps: 8.5)]
            )
        )

        await store.send(.gpsSpeedReceived(-1)) {
            $0.speedMPS = nil
            $0.activeSpeedSource = .none
            // speedSamples unchanged
        }
    }

    @Test("Watermark series downsamples to at most watermarkResolution points")
    func watermarkDownsamples() {
        let many = (0..<200).map {
            SpeedSample(time: Date(timeIntervalSince1970: Double($0)), mps: Double($0))
        }
        #expect(
            SpeedFeature.State(speedSamples: many).watermarkSamples.count
                == SpeedFeature.watermarkResolution
        )

        let few = (0..<10).map {
            SpeedSample(time: Date(timeIntervalSince1970: Double($0)), mps: Double($0))
        }
        #expect(SpeedFeature.State(speedSamples: few).watermarkSamples.count == 10)
    }

    @Test("Downsampling averages each bucket's time as well as its speed (#140)")
    func bucketAveragedKeepsTimeAxis() {
        let samples = (0..<120).map {
            SpeedSample(time: Date(timeIntervalSinceReferenceDate: Double($0)), mps: Double($0) * 2)
        }
        let buckets = samples.bucketAveraged(to: 60)
        #expect(buckets.count == 60)
        #expect(buckets.first == SpeedSample(time: Date(timeIntervalSinceReferenceDate: 0.5), mps: 1))
        #expect(buckets.last == SpeedSample(time: Date(timeIntervalSinceReferenceDate: 118.5), mps: 237))
        #expect(Array(samples.prefix(10)).bucketAveraged(to: 60) == Array(samples.prefix(10)))
    }

    @Test("The last bucket always holds the newest sample (#140 review)")
    func bucketAveragedKeepsNewestSample() {
        // 123 is a count where floating-point bucket edges ended one short and dropped it.
        for count in [61, 123, 245, 490, 3_600] {
            let samples = (0..<count).map { SpeedSample(time: Date(timeIntervalSinceReferenceDate: Double($0)), mps: 0) }
                + [SpeedSample(time: Date(timeIntervalSinceReferenceDate: Double(count)), mps: 1_000)]
            #expect(samples.bucketAveraged(to: 60).last!.mps > 0, "count \(count + 1)")
        }
    }

    // MARK: - BLE priority / fallback / promotion

    /// Mid-ride on the wheel sensor: a live link, with a GPS shadow value behind it.
    private static var onSensor: SpeedFeature.State {
        SpeedFeature.State(
            speedMPS: 6.0,
            activeSpeedSource: .bleWheel,
            connectionState: .active,
            latestGPSSpeedMPS: 5.5,
            pairedSensorName: "Wahoo RPM"
        )
    }

    @Test("Readings stopping while the link stays .active fall back to GPS, with the banner (#390)")
    func silentSensorOnALiveLinkFallsBack() async {
        let clock = TestClock()
        let store = makeStore(initialState: Self.onSensor, clock: clock)

        await store.send(.bleSpeedReceived(6.1)) {
            $0.speedMPS = 6.1
            $0.speedSamples = [SpeedSample(time: Self.testDate, mps: 6.1)]
        }
        // The link never leaves `.active`: the data's absence is the only signal.
        await clock.advance(by: SpeedFeature.staleDataWindow)
        await store.receive(\.bleFallbackTimedOut) {
            $0.speedMPS = 5.5
            $0.activeSpeedSource = .gps
            $0.sourceSwitchBanner = SpeedFeature.gpsFallbackBannerText(sensorName: "Wahoo RPM")
            $0.lastFallbackBannerAt = Self.testDate
        }
        await clock.advance(by: SpeedFeature.bannerDismissDelay)
        await store.receive(\.bannerDismissed) {
            $0.sourceSwitchBanner = nil
        }
    }

    @Test("Each reading restarts the stale-data window")
    func eachReadingRestartsTheWindow() async {
        let clock = TestClock()
        let store = makeStore(initialState: Self.onSensor, clock: clock)

        // 9 s of readings 3 s apart: a window counted from the first would fire mid-loop,
        // and its unasserted action would fail the next send.
        var samples: [SpeedSample] = []
        for mps in [6.1, 6.2, 6.3] {
            samples.append(SpeedSample(time: Self.testDate, mps: mps))
            await store.send(.bleSpeedReceived(mps)) {
                $0.speedMPS = mps
                $0.speedSamples = samples
            }
            await clock.advance(by: .seconds(3))
        }
        await clock.advance(by: SpeedFeature.staleDataWindow - .seconds(3))
        await store.receive(\.bleFallbackTimedOut) {
            $0.speedMPS = 5.5
            $0.activeSpeedSource = .gps
            $0.sourceSwitchBanner = SpeedFeature.gpsFallbackBannerText(sensorName: "Wahoo RPM")
            $0.lastFallbackBannerAt = Self.testDate
        }
        await clock.advance(by: SpeedFeature.bannerDismissDelay)
        await store.receive(\.bannerDismissed) {
            $0.sourceSwitchBanner = nil
        }
    }

    @Test("A flapping link neither restarts nor cancels the window (#390)")
    func flappingLinkDoesNotDriveTheFallback() async {
        let clock = TestClock()
        let store = makeStore(initialState: Self.onSensor, clock: clock)

        await store.send(.bleSpeedReceived(6.1)) {
            $0.speedMPS = 6.1
            $0.speedSamples = [SpeedSample(time: Self.testDate, mps: 6.1)]
        }
        // A drop and a recovery every second, with no data: the old connection-driven
        // timer restarted on each `.reconnecting` and died on each `.active`.
        for connection: BLECSCClient.ConnectionState in [.reconnecting, .active, .reconnecting] {
            await clock.advance(by: .seconds(1))
            await store.send(.bleConnectionChanged(connection)) {
                $0.connectionState = connection
            }
        }
        await clock.advance(by: SpeedFeature.staleDataWindow - .seconds(3))
        await store.receive(\.bleFallbackTimedOut) {
            $0.speedMPS = 5.5
            $0.activeSpeedSource = .gps
            $0.sourceSwitchBanner = SpeedFeature.gpsFallbackBannerText(sensorName: "Wahoo RPM")
            $0.lastFallbackBannerAt = Self.testDate
        }
        await clock.advance(by: SpeedFeature.bannerDismissDelay)
        await store.receive(\.bannerDismissed) {
            $0.sourceSwitchBanner = nil
        }
    }

    @Test("A stop on a healthy sensor stays on the sensor (#390)")
    func healthySensorStopDoesNotFallBack() async {
        let clock = TestClock()
        let store = makeStore(initialState: Self.onSensor, clock: clock)

        // What `CSCCalculator` emits at 1 Hz through a stop: a reading, two silent
        // duplicates, 0 on the third, zeros while stopped, a silent re-prime as the wheel
        // turns again, then readings. The 3 s gap is the longest; a window that short
        // fires during it and fails the next send.
        let emitted: [Double?] = [2.0, nil, nil, 0, 0, 0, 0, nil, 1.5, 3.0]
        var samples: [SpeedSample] = []
        for mps in emitted {
            if let mps {
                samples.append(SpeedSample(time: Self.testDate, mps: mps))
                await store.send(.bleSpeedReceived(mps)) {
                    $0.speedMPS = mps
                    $0.speedSamples = samples
                }
            }
            await clock.advance(by: .seconds(1))
        }

        // Still guarded afterwards: the sensor actually going quiet falls back as usual.
        await clock.advance(by: SpeedFeature.staleDataWindow - .seconds(1))
        await store.receive(\.bleFallbackTimedOut) {
            $0.speedMPS = 5.5
            $0.activeSpeedSource = .gps
            $0.sourceSwitchBanner = SpeedFeature.gpsFallbackBannerText(sensorName: "Wahoo RPM")
            $0.lastFallbackBannerAt = Self.testDate
        }
        await clock.advance(by: SpeedFeature.bannerDismissDelay)
        await store.receive(\.bannerDismissed) {
            $0.sourceSwitchBanner = nil
        }
    }

    @Test("Fallback with no GPS fix available clears the displayed speed, banner falls back to a generic name")
    func fallbackWithNoGPSFix() async {
        let clock = TestClock()
        let store = makeStore(
            initialState: SpeedFeature.State(
                speedMPS: 6.0,
                activeSpeedSource: .bleWheel
            ),
            clock: clock
        )

        await store.send(.bleSpeedReceived(6.0)) {
            $0.speedSamples = [SpeedSample(time: Self.testDate, mps: 6.0)]
        }
        await clock.advance(by: SpeedFeature.staleDataWindow)
        await store.receive(\.bleFallbackTimedOut) {
            $0.speedMPS = nil
            $0.activeSpeedSource = .none
            $0.sourceSwitchBanner = SpeedFeature.gpsFallbackBannerText(sensorName: nil)
            $0.lastFallbackBannerAt = Self.testDate
        }
        await clock.advance(by: SpeedFeature.bannerDismissDelay)
        await store.receive(\.bannerDismissed) {
            $0.sourceSwitchBanner = nil
        }
    }

    @Test(".reconnecting while GPS (not BLE) is active does not arm the fallback timer")
    func reconnectingWhileGPSActiveIsNoop() async {
        let clock = TestClock()
        let store = makeStore(
            initialState: SpeedFeature.State(speedMPS: 4.0, activeSpeedSource: .gps),
            clock: clock
        )

        await store.send(.bleConnectionChanged(.reconnecting)) {
            $0.connectionState = .reconnecting
        }
        await clock.advance(by: .seconds(60))
        // No .bleFallbackTimedOut fires — an unasserted receive fails the test.
    }

    @Test("GPS shadow-value update while BLE is active only touches latestGPSSpeedMPS")
    func gpsShadowValueWhileBLEActive() async {
        let store = makeStore(
            initialState: SpeedFeature.State(speedMPS: 9.0, activeSpeedSource: .bleWheel)
        )

        await store.send(.gpsSpeedReceived(4.0)) {
            $0.latestGPSSpeedMPS = 4.0
            // Displayed speedMPS/activeSpeedSource/speedSamples are untouched.
        }
    }

    @Test("BLE → GPS → BLE: the first reading after a fallback puts the sensor back on screen")
    func bleToGPSToBLERoundTrip() async {
        let clock = TestClock()
        let store = makeStore(initialState: Self.onSensor, clock: clock)

        // Outbound leg: the sensor goes quiet and the shadow value is promoted.
        await store.send(.bleSpeedReceived(6.1)) {
            $0.speedMPS = 6.1
            $0.speedSamples = [SpeedSample(time: Self.testDate, mps: 6.1)]
        }
        await clock.advance(by: SpeedFeature.staleDataWindow)
        await store.receive(\.bleFallbackTimedOut) {
            $0.speedMPS = 5.5
            $0.activeSpeedSource = .gps
            $0.sourceSwitchBanner = SpeedFeature.gpsFallbackBannerText(sensorName: "Wahoo RPM")
            $0.lastFallbackBannerAt = Self.testDate
        }

        // Return leg: data arriving *is* the promotion — there is no separate action
        // for it, so nothing else in the suite would catch this regressing. The
        // displayed value must be the sensor's, not the GPS shadow it replaces.
        await clock.advance(by: .seconds(1))
        await store.send(.bleSpeedReceived(6.4)) {
            $0.speedMPS = 6.4
            $0.activeSpeedSource = .bleWheel
            $0.speedSamples = [
                SpeedSample(time: Self.testDate, mps: 6.1),
                SpeedSample(time: Self.testDate, mps: 6.4),
            ]
        }

        // Recovery does not retract the notice: the rider was told the source moved, so
        // the banner still runs its full dismissal delay. And the promoted sensor is
        // guarded again: the reading re-armed the watchdog.
        await clock.advance(by: SpeedFeature.staleDataWindow)
        await store.receive(\.bannerDismissed) {
            $0.sourceSwitchBanner = nil
        }
        await store.receive(\.bleFallbackTimedOut) {
            $0.speedMPS = 5.5
            $0.activeSpeedSource = .gps
        }
    }

    @Test("A flapping sensor switches source every cycle but shows the banner once per cooldown (#390)")
    func flappingSensorBannerCooldown() async {
        let clock = TestClock()
        let store = makeStore(initialState: Self.onSensor, clock: clock)
        var samples: [SpeedSample] = []

        func readingThenSilence(_ mps: Double, at time: Date) async {
            samples.append(SpeedSample(time: time, mps: mps))
            await store.send(.bleSpeedReceived(mps)) {
                $0.speedMPS = mps
                $0.activeSpeedSource = .bleWheel
                $0.speedSamples = samples
            }
            await clock.advance(by: SpeedFeature.staleDataWindow)
        }

        // First drop: the rider is told.
        await readingThenSilence(6.1, at: Self.testDate)
        await store.receive(\.bleFallbackTimedOut) {
            $0.speedMPS = 5.5
            $0.activeSpeedSource = .gps
            $0.sourceSwitchBanner = SpeedFeature.gpsFallbackBannerText(sensorName: "Wahoo RPM")
            $0.lastFallbackBannerAt = Self.testDate
        }
        await clock.advance(by: SpeedFeature.bannerDismissDelay)
        await store.receive(\.bannerDismissed) {
            $0.sourceSwitchBanner = nil
        }

        // Further drops inside the cooldown: the source still switches, the banner stays away.
        for mps in [6.2, 6.3] {
            await readingThenSilence(mps, at: Self.testDate)
            await store.receive(\.bleFallbackTimedOut) {
                $0.speedMPS = 5.5
                $0.activeSpeedSource = .gps
            }
        }

        // Once the cooldown has passed, the next drop is announced again.
        let later = Self.testDate.addingTimeInterval(SpeedFeature.fallbackBannerCooldown)
        store.dependencies.date = .constant(later)
        await readingThenSilence(6.4, at: later)
        await store.receive(\.bleFallbackTimedOut) {
            $0.speedMPS = 5.5
            $0.activeSpeedSource = .gps
            $0.sourceSwitchBanner = SpeedFeature.gpsFallbackBannerText(sensorName: "Wahoo RPM")
            $0.lastFallbackBannerAt = later
        }
        await clock.advance(by: SpeedFeature.bannerDismissDelay)
        await store.receive(\.bannerDismissed) {
            $0.sourceSwitchBanner = nil
        }
    }

    @Test("Terminal disconnect while still BLE-sourced falls back immediately and disarms the watchdog")
    func terminalDisconnectFallsBackImmediately() async {
        let clock = TestClock()
        let store = makeStore(
            initialState: SpeedFeature.State(
                speedMPS: 6.0,
                activeSpeedSource: .bleWheel,
                latestGPSSpeedMPS: 5.0
            ),
            clock: clock
        )

        await store.send(.bleSpeedReceived(6.0)) {
            $0.speedSamples = [SpeedSample(time: Self.testDate, mps: 6.0)]
        }
        await store.send(.bleConnectionChanged(.disconnected)) {
            $0.connectionState = .disconnected
            $0.speedMPS = 5.0
            $0.activeSpeedSource = .gps
            $0.sourceSwitchBanner = SpeedFeature.gpsFallbackBannerText(sensorName: nil)
            $0.lastFallbackBannerAt = Self.testDate
        }
        await clock.advance(by: SpeedFeature.bannerDismissDelay)
        await store.receive(\.bannerDismissed) {
            $0.sourceSwitchBanner = nil
        }
        // No .bleFallbackTimedOut follows — an unasserted receive fails the test.
        await clock.advance(by: SpeedFeature.staleDataWindow)
    }
}
