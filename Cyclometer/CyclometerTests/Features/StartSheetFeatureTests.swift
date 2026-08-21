import Foundation
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

        await store.send(.radarStatusUpdated(.active)) {
            $0.setStatus(.connected, for: .radar)
        }
        await store.send(.radarStatusUpdated(.disconnected)) {
            $0.setStatus(.searching, for: .radar)
        }
        // Everything short of connected collapses into Searching — the sheet holds a
        // pairing scan open, so a sensor it is not talking to is one it is looking for.
        await store.send(.radarStatusUpdated(.connected)) {
            $0.setStatus(.connected, for: .radar)
        }
        await store.send(.radarStatusUpdated(.reconnecting)) {
            $0.setStatus(.searching, for: .radar)
        }
        await store.send(.radarStatusUpdated(.scanning))
        await store.send(.radarStatusUpdated(.connecting))
    }

    @Test("HR's bool maps to connected / searching — it is not the pairing record")
    func hrPairingMapping() async {
        let store = TestStore(initialState: StartSheetFeature.State()) {
            StartSheetFeature()
        }

        await store.send(.hrPairingUpdated(true)) {
            $0.setStatus(.connected, for: .heartRate)
        }
        await store.send(.hrPairingUpdated(false)) {
            $0.setStatus(.searching, for: .heartRate)
        }
    }

    @Test("Speed and cadence CSC states update their own rows independently")
    func speedCadenceMapping() async {
        let store = TestStore(initialState: StartSheetFeature.State()) {
            StartSheetFeature()
        }

        await store.send(.cadenceStatusUpdated(.connected)) {
            $0.setStatus(.connected, for: .cadence)
        }
        #expect(store.state.sensors.first { $0.kind == .speed }?.status == .searching)
    }



    // MARK: Which rows the sheet shows

    /// Seeded in the same dependency scope the store reads from, otherwise the seed and
    /// the store see different storage — the idiom `DeviceManagementFeatureTests` uses.
    private func makeStore(
        sensors: [SensorRow] = SensorRow.Kind.allCases.map { SensorRow(kind: $0) },
        pairedSensors: [PairedSensor] = []
    ) -> TestStoreOf<StartSheetFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.pairedSensors = pairedSensors }
            return TestStore(initialState: StartSheetFeature.State(sensors: sensors)) {
                StartSheetFeature()
            } withDependencies: {
                $0.defaultFileStorage = storage
            }
        }
    }

    /// The point of the change: a paired sensor the app is not connected to is the
    /// sheet's *normal* state, because nothing scans until the ride starts.
    @Test("A paired sensor that is not connected is still listed, named, and Searching")
    func notConnectedPairedSensorIsListed() {
        let store = makeStore(
            pairedSensors: [
                PairedSensor(peripheralID: UUID(), role: .radar, displayName: "Varia RTL515")
            ]
        )

        let rows = store.state.pairedRows
        #expect(rows.map(\.kind) == [.radar])
        // Named from the record, which is the only source that survives being out of range.
        #expect(rows[0].name == "Varia RTL515")
        #expect(rows[0].status == .searching)
        #expect(rows[0].status.badge.label == "Searching")
    }

    @Test("An unpaired category has no row at all")
    func unpairedCategoriesAreAbsent() {
        let store = makeStore(
            sensors: [
                SensorRow(kind: .radar, status: .connected),
                SensorRow(kind: .heartRate, status: .searching),
                SensorRow(kind: .speed, status: .searching),
                SensorRow(kind: .cadence, status: .searching)
            ],
            pairedSensors: [
                PairedSensor(peripheralID: UUID(), role: .radar, displayName: "Varia RTL515"),
                PairedSensor(peripheralID: UUID(), role: .speed, displayName: "Wahoo RPM")
            ]
        )

        #expect(store.state.pairedRows.map(\.kind) == [.radar, .speed])
    }

    /// Live status is not what decides the row's existence — that was the bug. A record
    /// with no client signal behind it still gets a row.
    @Test("Rows come from the records, not from live client status")
    func rowsComeFromRecordsNotStatus() {
        let store = makeStore(pairedSensors: [])
        #expect(store.state.pairedRows.isEmpty)

        let paired = makeStore(
            pairedSensors: SensorRow.Kind.allCases.map {
                PairedSensor(peripheralID: UUID(), role: $0.role, displayName: nil)
            }
        )
        #expect(paired.state.pairedRows.count == SensorRow.Kind.allCases.count)
        #expect(paired.state.pairedRows.allSatisfy { $0.status == .searching })
    }

    @Test("Every category maps to the role its records are keyed by")
    func kindsMapToRoles() {
        #expect(SensorRow.Kind.allCases.map(\.role) == [.radar, .heartRate, .speed, .cadence])
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
