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

    @Test("Tap to Pair is a no-op hook until the pairing flow exists")
    func pairButtonIsNoOp() async {
        let store = TestStore(initialState: StartSheetFeature.State()) {
            StartSheetFeature()
        }

        await store.send(.pairButtonTapped(.speed))
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

    @Test("Battery updates land on the addressed row only, and clear on nil")
    func batteryUpdatesAddressedRow() async {
        let store = TestStore(initialState: StartSheetFeature.State()) {
            StartSheetFeature()
        }

        await store.send(.batteryUpdated(.radar, 82)) {
            $0.setBattery(82, for: .radar)
        }
        // A second row's level must not disturb the first.
        await store.send(.batteryUpdated(.heartRate, 14)) {
            $0.setBattery(14, for: .heartRate)
        }
        #expect(store.state.sensors.first { $0.kind == .radar }?.batteryPercent == 82)

        // Disconnecting clears it — the row must not keep showing a stale level.
        await store.send(.batteryUpdated(.radar, nil)) {
            $0.setBattery(nil, for: .radar)
        }
    }

    @Test("Appearing subscribes to each client's battery stream")
    func taskSubscribesToBatteryStreams() async {
        let (radarStream, radarContinuation) = AsyncStream<Int?>.makeStream()
        let (hrStream, hrContinuation) = AsyncStream<Int?>.makeStream()
        let (speedStream, speedContinuation) = AsyncStream<Int?>.makeStream()
        let (cadenceStream, cadenceContinuation) = AsyncStream<Int?>.makeStream()

        var radar = VariaRadarClient.testValue
        radar.batteryLevel = { radarStream }
        var hr = BLEHRClient.testValue
        hr.batteryLevel = { hrStream }
        var csc = BLECSCClient.testValue
        csc.batteryLevel = { role in role == .speed ? speedStream : cadenceStream }

        let store = TestStore(initialState: StartSheetFeature.State()) {
            StartSheetFeature()
        } withDependencies: {
            $0.variaRadarClient = radar
            $0.bleHRClient = hr
            $0.bleCSCClient = csc
        }

        await store.send(.task)

        radarContinuation.yield(91)
        await store.receive(\.batteryUpdated) { $0.setBattery(91, for: .radar) }
        hrContinuation.yield(47)
        await store.receive(\.batteryUpdated) { $0.setBattery(47, for: .heartRate) }
        speedContinuation.yield(63)
        await store.receive(\.batteryUpdated) { $0.setBattery(63, for: .speed) }
        cadenceContinuation.yield(8)
        await store.receive(\.batteryUpdated) { $0.setBattery(8, for: .cadence) }

        radarContinuation.finish()
        hrContinuation.finish()
        speedContinuation.finish()
        cadenceContinuation.finish()
        await store.finish()
    }
}
