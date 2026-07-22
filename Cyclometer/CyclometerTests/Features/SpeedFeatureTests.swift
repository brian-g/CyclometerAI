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
        date: Date = Self.testDate
    ) -> TestStoreOf<SpeedFeature> {
        TestStore(initialState: initialState) {
            SpeedFeature()
        } withDependencies: {
            $0.date = .constant(date)
            $0.continuousClock = clock
            $0.bleCSCClient = bleCSCClient
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

    @Test("Start listening subscribes to BLE speed and connection-state streams")
    func startListeningSubscribesToBLEStreams() async {
        let (speedStream, speedContinuation) = AsyncStream<Double>.makeStream()
        let (connStream, connContinuation) = AsyncStream<BLECSCClient.ConnectionState>.makeStream()
        var ble = BLECSCClient.testValue
        ble.speed = { speedStream }
        ble.connectionState = { _ in connStream }

        let store = makeStore(bleCSCClient: ble)
        await store.send(.startListening)

        connContinuation.yield(.scanning)
        await store.receive(\.bleConnectionChanged) {
            $0.connectionState = .scanning
        }

        speedContinuation.yield(3.5)
        await store.receive(\.bleSpeedReceived) {
            $0.speedMPS = 3.5
            $0.activeSpeedSource = .bleWheel
            $0.speedSamples = [SpeedSample(time: Self.testDate, mps: 3.5)]
        }

        speedContinuation.finish()
        connContinuation.finish()
        await store.finish()
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

    // MARK: - BLE priority / fallback / promotion

    @Test("BLE speed cancels a pending fallback timer")
    func bleSpeedCancelsPendingFallback() async {
        let clock = TestClock()
        let store = makeStore(clock: clock)

        await store.send(.bleSpeedReceived(6.0)) {
            $0.speedMPS = 6.0
            $0.activeSpeedSource = .bleWheel
            $0.speedSamples = [SpeedSample(time: Self.testDate, mps: 6.0)]
        }
        await store.send(.bleConnectionChanged(.reconnecting)) {
            $0.connectionState = .reconnecting
        }
        // Data resumes before the 5s fallback fires — cancels the timer.
        await store.send(.bleSpeedReceived(6.2)) {
            $0.speedMPS = 6.2
            $0.speedSamples = [
                SpeedSample(time: Self.testDate, mps: 6.0),
                SpeedSample(time: Self.testDate, mps: 6.2),
            ]
        }
        // No .bleFallbackTimedOut should fire — an unasserted receive fails the test.
        await clock.advance(by: .seconds(60))
    }

    @Test("Fallback after 5s promotes the GPS shadow value and shows/dismisses the banner")
    func fallbackAfter5sWithGPSShadowValue() async {
        let clock = TestClock()
        let store = makeStore(
            initialState: SpeedFeature.State(
                speedMPS: 6.0,
                activeSpeedSource: .bleWheel,
                latestGPSSpeedMPS: 5.5
            ),
            clock: clock
        )

        await store.send(.bleConnectionChanged(.reconnecting)) {
            $0.connectionState = .reconnecting
        }
        await clock.advance(by: SpeedFeature.fallbackDelay)
        await store.receive(\.bleFallbackTimedOut) {
            $0.speedMPS = 5.5
            $0.activeSpeedSource = .gps
            $0.sourceSwitchBanner = SpeedFeature.gpsFallbackBannerText
        }
        await clock.advance(by: SpeedFeature.bannerDismissDelay)
        await store.receive(\.bannerDismissed) {
            $0.sourceSwitchBanner = nil
        }
    }

    @Test("Fallback with no GPS fix available clears the displayed speed")
    func fallbackWithNoGPSFix() async {
        let clock = TestClock()
        let store = makeStore(
            initialState: SpeedFeature.State(
                speedMPS: 6.0,
                activeSpeedSource: .bleWheel
            ),
            clock: clock
        )

        await store.send(.bleConnectionChanged(.reconnecting)) {
            $0.connectionState = .reconnecting
        }
        await clock.advance(by: SpeedFeature.fallbackDelay)
        await store.receive(\.bleFallbackTimedOut) {
            $0.speedMPS = nil
            $0.activeSpeedSource = .none
            $0.sourceSwitchBanner = SpeedFeature.gpsFallbackBannerText
        }
        await clock.advance(by: SpeedFeature.bannerDismissDelay)
        await store.receive(\.bannerDismissed) {
            $0.sourceSwitchBanner = nil
        }
    }

    @Test("Recovery within 5s cancels the timer — no fallback, no banner")
    func recoveryWithinFallbackWindow() async {
        let clock = TestClock()
        let store = makeStore(
            initialState: SpeedFeature.State(
                speedMPS: 6.0,
                activeSpeedSource: .bleWheel,
                latestGPSSpeedMPS: 5.5
            ),
            clock: clock
        )

        await store.send(.bleConnectionChanged(.reconnecting)) {
            $0.connectionState = .reconnecting
        }
        await clock.advance(by: .seconds(4))
        await store.send(.bleConnectionChanged(.active)) {
            $0.connectionState = .active
        }
        await clock.advance(by: .seconds(60))
        // No .bleFallbackTimedOut fires — an unasserted receive fails the test.
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

    @Test("Terminal disconnect while still BLE-sourced falls back immediately")
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

        await store.send(.bleConnectionChanged(.disconnected)) {
            $0.connectionState = .disconnected
            $0.speedMPS = 5.0
            $0.activeSpeedSource = .gps
            $0.sourceSwitchBanner = SpeedFeature.gpsFallbackBannerText
        }
        await clock.advance(by: SpeedFeature.bannerDismissDelay)
        await store.receive(\.bannerDismissed) {
            $0.sourceSwitchBanner = nil
        }
    }
}
