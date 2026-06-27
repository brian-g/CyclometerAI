import Testing
import ComposableArchitecture
@testable import Cyclometer

@MainActor
@Suite("SpeedFeature")
struct SpeedFeatureTests {

    @Test("Valid GPS speed sets speedMPS, source, and appends to history")
    func validGPSSpeed() async {
        let store = TestStore(initialState: SpeedFeature.State()) {
            SpeedFeature()
        }

        await store.send(.gpsSpeedReceived(8.5)) {
            $0.speedMPS = 8.5
            $0.activeSpeedSource = .gps
            $0.speedHistory = [8.5]
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

    @Test("Start listening skips BLE when no peripheral is paired")
    func startListeningWithoutPeripheralIsNoop() async {
        let store = TestStore(initialState: SpeedFeature.State()) {
            SpeedFeature()
        }

        await store.send(.startListening)
    }

    @Test("Speed history is capped at 60 samples")
    func speedHistoryCappedAt60() async {
        let initial = SpeedFeature.State(speedHistory: Array(repeating: 8.0, count: 60))
        let store = TestStore(initialState: initial) {
            SpeedFeature()
        }

        await store.send(.gpsSpeedReceived(9.0)) {
            $0.speedMPS = 9.0
            $0.activeSpeedSource = .gps
            var expected = Array(repeating: 8.0, count: 59)
            expected.append(9.0)
            $0.speedHistory = expected
        }
    }

    @Test("Invalid GPS speed does not append to speed history")
    func invalidSpeedSkipsHistory() async {
        let store = TestStore(
            initialState: SpeedFeature.State(speedMPS: 8.5, activeSpeedSource: .gps, speedHistory: [8.5])
        ) {
            SpeedFeature()
        }

        await store.send(.gpsSpeedReceived(-1)) {
            $0.speedMPS = nil
            $0.activeSpeedSource = .none
            // speedHistory unchanged
        }
    }
}
