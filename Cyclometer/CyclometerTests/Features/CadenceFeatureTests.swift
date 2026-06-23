import Testing
import ComposableArchitecture
@testable import Cyclometer

@MainActor
@Suite("CadenceFeature")
struct CadenceFeatureTests {

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
}
