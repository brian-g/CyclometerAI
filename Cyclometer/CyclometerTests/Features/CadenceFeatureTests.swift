import Testing
import Foundation
import ComposableArchitecture
@testable import Cyclometer

@MainActor
@Suite("CadenceFeature")
struct CadenceFeatureTests {

    private static let testDate = Date(timeIntervalSince1970: 1_000_000)

    private func makeStore(
        initialState: CadenceFeature.State = CadenceFeature.State(),
        clock: TestClock<Duration> = TestClock(),
        bleCSCClient: BLECSCClient = .testValue,
        date: Date = Self.testDate
    ) -> TestStoreOf<CadenceFeature> {
        TestStore(initialState: initialState) {
            CadenceFeature()
        } withDependencies: {
            $0.date = .constant(date)
            $0.continuousClock = clock
            $0.bleCSCClient = bleCSCClient
        }
    }

    @Test("Start listening subscribes to BLE cadence and connection-state streams")
    func startListeningSubscribesToBLEStreams() async {
        let (cadenceStream, cadenceContinuation) = AsyncStream<Double>.makeStream()
        let (connStream, connContinuation) = AsyncStream<BLECSCClient.ConnectionState>.makeStream()
        var ble = BLECSCClient.testValue
        ble.cadence = { cadenceStream }
        ble.connectionState = { _ in connStream }

        let store = makeStore(bleCSCClient: ble)
        await store.send(.startListening)

        connContinuation.yield(.scanning)
        await store.receive(\.bleConnectionChanged) {
            $0.connectionState = .scanning
        }

        cadenceContinuation.yield(92)
        await store.receive(\.cadenceReceived) {
            $0.cadenceRPM = 92
            $0.cadenceSamples = [CadenceSample(time: Self.testDate, rpm: 92)]
            $0.pedalingSampleCount = 1
            $0.cadenceSum = 92
            $0.maxCadenceRPM = 92
        }

        cadenceContinuation.finish()
        connContinuation.finish()
        await store.finish()
    }

    @Test("Initial cadenceRPM is nil")
    func initialCadenceIsNil() async {
        let store = makeStore()

        #expect(store.state.cadenceRPM == nil)
    }

    @Test("Initial connectionState is disconnected")
    func initialConnectionStateIsDisconnected() async {
        let store = makeStore()

        #expect(store.state.connectionState == .disconnected)
    }

    @Test("cadenceReceived sets rpm, appends a sample, and updates max")
    func cadenceReceivedUpdatesState() async {
        let store = makeStore()

        await store.send(.cadenceReceived(92)) {
            $0.cadenceRPM = 92
            $0.cadenceSamples = [CadenceSample(time: Self.testDate, rpm: 92)]
            $0.pedalingSampleCount = 1
            $0.cadenceSum = 92
            $0.maxCadenceRPM = 92
        }
    }

    @Test("Average cadence is the mean of non-zero readings; coasting is excluded")
    func averageExcludesCoasting() async {
        let store = makeStore()

        await store.send(.cadenceReceived(80)) {
            $0.cadenceRPM = 80
            $0.cadenceSamples = [CadenceSample(time: Self.testDate, rpm: 80)]
            $0.pedalingSampleCount = 1
            $0.cadenceSum = 80
            $0.maxCadenceRPM = 80
        }
        // Coasting reading: stored for the watermark but excluded from the average.
        await store.send(.cadenceReceived(0)) {
            $0.cadenceRPM = 0
            $0.cadenceSamples = [
                CadenceSample(time: Self.testDate, rpm: 80),
                CadenceSample(time: Self.testDate, rpm: 0)
            ]
        }
        await store.send(.cadenceReceived(100)) {
            $0.cadenceRPM = 100
            $0.cadenceSamples = [
                CadenceSample(time: Self.testDate, rpm: 80),
                CadenceSample(time: Self.testDate, rpm: 0),
                CadenceSample(time: Self.testDate, rpm: 100)
            ]
            $0.pedalingSampleCount = 2
            $0.cadenceSum = 180
            $0.maxCadenceRPM = 100
        }

        #expect(store.state.averageCadenceRPM == 90)   // (80 + 100) / 2, coasting 0 excluded
    }

    @Test("Negative cadence clears rpm and appends no sample")
    func negativeCadenceClearsState() async {
        let store = makeStore(
            initialState: CadenceFeature.State(
                cadenceRPM: 80,
                cadenceSamples: [CadenceSample(time: Self.testDate, rpm: 80)]
            )
        )

        await store.send(.cadenceReceived(-1)) {
            $0.cadenceRPM = nil
            // cadenceSamples unchanged
        }
    }

    @Test("Samples older than the history window are pruned")
    func prunesSamplesOlderThanWindow() async {
        let start = Date(timeIntervalSince1970: 0)
        let stale = CadenceSample(time: start, rpm: 80)                              // t=0
        let recent = CadenceSample(time: start.addingTimeInterval(1800), rpm: 90)    // t=1800
        let now = start.addingTimeInterval(CadenceFeature.historyWindow + 1)         // t=3601

        let store = makeStore(
            initialState: CadenceFeature.State(cadenceSamples: [stale, recent]),
            date: now
        )

        await store.send(.cadenceReceived(95)) {
            $0.cadenceRPM = 95
            // stale (t=0) is now older than the window → pruned; recent + new stay.
            $0.cadenceSamples = [recent, CadenceSample(time: now, rpm: 95)]
            $0.pedalingSampleCount = 1
            $0.cadenceSum = 95
            $0.maxCadenceRPM = 95
        }
    }

    @Test("Watermark series downsamples to at most watermarkResolution points")
    func watermarkDownsamples() {
        let many = (0..<200).map {
            CadenceSample(time: Date(timeIntervalSince1970: Double($0)), rpm: Double($0))
        }
        #expect(
            CadenceFeature.State(cadenceSamples: many).watermarkSamples.count
                == CadenceFeature.watermarkResolution
        )

        let few = (0..<10).map {
            CadenceSample(time: Date(timeIntervalSince1970: Double($0)), rpm: Double($0))
        }
        #expect(CadenceFeature.State(cadenceSamples: few).watermarkSamples.count == 10)
    }

    // MARK: - BLE reconnect grace window

    @Test("Cadence data cancels a pending reconnect timer")
    func cadenceReceivedCancelsPendingReconnectTimer() async {
        let clock = TestClock()
        let store = makeStore(
            initialState: CadenceFeature.State(cadenceRPM: 80),
            clock: clock
        )

        await store.send(.bleConnectionChanged(.reconnecting)) {
            $0.connectionState = .reconnecting
        }
        // Data resumes before the grace window elapses — cancels the timer.
        await store.send(.cadenceReceived(82)) {
            $0.cadenceRPM = 82
            $0.cadenceSamples = [CadenceSample(time: Self.testDate, rpm: 82)]
            $0.pedalingSampleCount = 1
            $0.cadenceSum = 82
            $0.maxCadenceRPM = 82
        }
        // No .cadenceReconnectTimedOut should fire — an unasserted receive fails the test.
        await clock.advance(by: .seconds(60))
    }

    @Test(".reconnecting with no current reading arms no timer")
    func reconnectingWithNoCurrentReadingIsNoop() async {
        let clock = TestClock()
        let store = makeStore(clock: clock)

        await store.send(.bleConnectionChanged(.reconnecting)) {
            $0.connectionState = .reconnecting
        }
        await clock.advance(by: .seconds(60))
        // No .cadenceReconnectTimedOut fires — an unasserted receive fails the test.
    }

    @Test("Reconnect timeout clears cadence to nil after the grace window")
    func reconnectTimeoutClearsCadenceAfterGraceWindow() async {
        let clock = TestClock()
        let store = makeStore(
            initialState: CadenceFeature.State(cadenceRPM: 80),
            clock: clock
        )

        await store.send(.bleConnectionChanged(.reconnecting)) {
            $0.connectionState = .reconnecting
        }
        await clock.advance(by: CadenceFeature.reconnectGraceDelay)
        await store.receive(\.cadenceReconnectTimedOut) {
            $0.cadenceRPM = nil
        }
    }

    @Test("Recovery within the grace window keeps the reading — no clear")
    func recoveryWithinGraceWindowKeepsReading() async {
        let clock = TestClock()
        let store = makeStore(
            initialState: CadenceFeature.State(cadenceRPM: 80),
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
        // No .cadenceReconnectTimedOut fires — an unasserted receive fails the test.
    }

    @Test("Terminal disconnect clears cadence immediately, no grace delay")
    func terminalDisconnectClearsImmediately() async {
        let store = makeStore(initialState: CadenceFeature.State(cadenceRPM: 80))

        await store.send(.bleConnectionChanged(.disconnected)) {
            $0.connectionState = .disconnected
            $0.cadenceRPM = nil
        }
    }
}
