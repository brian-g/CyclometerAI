import Testing
import Foundation
import ComposableArchitecture
@testable import Cyclometer

@MainActor
@Suite("CadenceFeature")
struct CadenceFeatureTests {

    private static let testDate = Date(timeIntervalSince1970: 1_000_000)

    // Placeholder, not real coverage — see the matching note in SpeedFeatureTests.
    // `BLECSCClient` is not injected here yet and nothing sets `pairedPeripheralId`.
    @Test("Start listening skips BLE when no peripheral is paired")
    func startListeningWithoutPeripheralIsNoop() async {
        let store = TestStore(initialState: CadenceFeature.State()) {
            CadenceFeature()
        }

        await store.send(.startListening)
    }

    @Test("Initial cadenceRPM is nil")
    func initialCadenceIsNil() async {
        let store = TestStore(initialState: CadenceFeature.State()) {
            CadenceFeature()
        }

        #expect(store.state.cadenceRPM == nil)
    }

    @Test("Initial connectionState is disconnected")
    func initialConnectionStateIsDisconnected() async {
        let store = TestStore(initialState: CadenceFeature.State()) {
            CadenceFeature()
        }

        #expect(store.state.connectionState == .disconnected)
    }

    @Test("cadenceReceived sets rpm, appends a sample, and updates max")
    func cadenceReceivedUpdatesState() async {
        let store = TestStore(initialState: CadenceFeature.State()) {
            CadenceFeature()
        } withDependencies: {
            $0.date = .constant(Self.testDate)
        }

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
        let store = TestStore(initialState: CadenceFeature.State()) {
            CadenceFeature()
        } withDependencies: {
            $0.date = .constant(Self.testDate)
        }

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
        let store = TestStore(
            initialState: CadenceFeature.State(
                cadenceRPM: 80,
                cadenceSamples: [CadenceSample(time: Self.testDate, rpm: 80)]
            )
        ) {
            CadenceFeature()
        }

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

        let store = TestStore(
            initialState: CadenceFeature.State(cadenceSamples: [stale, recent])
        ) {
            CadenceFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }

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
}
