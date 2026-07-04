import Testing
import ComposableArchitecture
@testable import Cyclometer

@MainActor
@Suite("StartSheetFeature")
struct StartSheetFeatureTests {

    @Test("Start Ride button emits the startRide delegate")
    func startRideEmitsDelegate() async {
        let store = TestStore(initialState: StartSheetFeature.State()) {
            StartSheetFeature()
        }

        await store.send(.startRideButtonTapped)
        await store.receive(.delegate(.startRide))
    }

    @Test("Cancel dismisses the sheet")
    func cancelDismisses() async {
        let isDismissed = LockIsolated(false)
        let store = TestStore(initialState: StartSheetFeature.State()) {
            StartSheetFeature()
        } withDependencies: {
            $0.dismiss = DismissEffect { isDismissed.setValue(true) }
        }

        await store.send(.cancelButtonTapped)
        #expect(isDismissed.value)
    }

    @Test("Radar connection states map to the radar row badge")
    func radarStatusMapping() async {
        let store = TestStore(initialState: StartSheetFeature.State()) {
            StartSheetFeature()
        }

        await store.send(.radarStatusUpdated(.scanning)) {
            $0.setStatus(.searching, for: .radar)
        }
        await store.send(.radarStatusUpdated(.active)) {
            $0.setStatus(.connected, for: .radar)
        }
        await store.send(.radarStatusUpdated(.disconnected)) {
            $0.setStatus(.notPaired, for: .radar)
        }
    }

    @Test("HR paired bool maps to connected / not paired only")
    func hrPairingMapping() async {
        let store = TestStore(initialState: StartSheetFeature.State()) {
            StartSheetFeature()
        }

        await store.send(.hrPairingUpdated(true)) {
            $0.setStatus(.connected, for: .heartRate)
        }
        await store.send(.hrPairingUpdated(false)) {
            $0.setStatus(.notPaired, for: .heartRate)
        }
    }

    @Test("Speed and cadence CSC states update their own rows independently")
    func speedCadenceMapping() async {
        let store = TestStore(initialState: StartSheetFeature.State()) {
            StartSheetFeature()
        }

        await store.send(.speedStatusUpdated(.connecting)) {
            $0.setStatus(.searching, for: .speed)
        }
        await store.send(.cadenceStatusUpdated(.connected)) {
            $0.setStatus(.connected, for: .cadence)
        }
    }
}
