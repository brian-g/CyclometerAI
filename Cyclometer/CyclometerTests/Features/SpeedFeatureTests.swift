import Testing
import Foundation
import ComposableArchitecture
@testable import Cyclometer

@MainActor
@Suite("SpeedFeature")
struct SpeedFeatureTests {

    private static let testDate = Date(timeIntervalSince1970: 1_000_000)

    @Test("Valid GPS speed sets speedMPS, source, and appends a timestamped sample")
    func validGPSSpeed() async {
        let store = TestStore(initialState: SpeedFeature.State()) {
            SpeedFeature()
        } withDependencies: {
            $0.date = .constant(Self.testDate)
        }

        await store.send(.gpsSpeedReceived(8.5)) {
            $0.speedMPS = 8.5
            $0.activeSpeedSource = .gps
            $0.speedSamples = [SpeedSample(time: Self.testDate, mps: 8.5)]
        }
    }

    @Test("Invalid GPS speed clears speedMPS and source")
    func invalidGPSSpeedClearsState() async {
        let store = TestStore(
            initialState: SpeedFeature.State(speedMPS: 8.5, activeSpeedSource: .gps)
        ) {
            SpeedFeature()
        }

        await store.send(.gpsSpeedReceived(-1)) {
            $0.speedMPS = nil
            $0.activeSpeedSource = .none
        }
    }

    // Placeholder, not real coverage: `BLECSCClient` is not yet injected here and
    // nothing sets `pairedPeripheralId`, so both sides of the guard return `.none`
    // and this would still pass with the guard deleted. It becomes meaningful once
    // BLE speed pairing lands — assert then that no subscription is attempted.
    @Test("Start listening skips BLE when no peripheral is paired")
    func startListeningWithoutPeripheralIsNoop() async {
        let store = TestStore(initialState: SpeedFeature.State()) {
            SpeedFeature()
        }

        await store.send(.startListening)
    }

    @Test("Samples older than the history window are pruned")
    func prunesSamplesOlderThanWindow() async {
        let start = Date(timeIntervalSince1970: 0)
        let stale = SpeedSample(time: start, mps: 5.0)                            // t=0
        let recent = SpeedSample(time: start.addingTimeInterval(1800), mps: 6.0)  // t=1800
        let now = start.addingTimeInterval(SpeedFeature.historyWindow + 1)        // t=3601

        let store = TestStore(
            initialState: SpeedFeature.State(speedSamples: [stale, recent])
        ) {
            SpeedFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }

        await store.send(.gpsSpeedReceived(7.0)) {
            $0.speedMPS = 7.0
            $0.activeSpeedSource = .gps
            // stale (t=0) is now older than the window → pruned; recent + new stay.
            $0.speedSamples = [recent, SpeedSample(time: now, mps: 7.0)]
        }
    }

    @Test("Invalid GPS speed does not append to speed samples")
    func invalidSpeedSkipsHistory() async {
        let store = TestStore(
            initialState: SpeedFeature.State(
                speedMPS: 8.5,
                activeSpeedSource: .gps,
                speedSamples: [SpeedSample(time: Self.testDate, mps: 8.5)]
            )
        ) {
            SpeedFeature()
        }

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
}
