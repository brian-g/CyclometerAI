import Testing
import ComposableArchitecture
@testable import Cyclometer

@MainActor
@Suite("SpeedFeature")
struct SpeedFeatureTests {

    @Test("Valid GPS speed sets speedMPS and source")
    func validGPSSpeed() async {
        let store = TestStore(initialState: SpeedFeature.State()) {
            SpeedFeature()
        }

        await store.send(.gpsSpeedReceived(8.5)) {
            $0.speedMPS = 8.5
            $0.activeSpeedSource = .gps
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
}
