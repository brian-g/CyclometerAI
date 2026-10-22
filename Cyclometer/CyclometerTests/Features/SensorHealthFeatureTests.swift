import ComposableArchitecture
import CoreBluetooth
import Foundation
import Testing
@testable import Cyclometer

@MainActor
@Suite("SensorHealthFeature")
struct SensorHealthFeatureTests {
    static let combo = UUID(1)     // a Wahoo RPM assigned Both
    static let radar = UUID(2)
    static let stranger = UUID(9)  // discovered by the shared central, never paired
    static let now = Date(timeIntervalSince1970: 1_000_000)

    static let paired = [
        PairedSensor(peripheralID: combo, role: .speed, displayName: "Wahoo RPM"),
        PairedSensor(peripheralID: combo, role: .cadence, displayName: "Wahoo RPM"),
        PairedSensor(peripheralID: radar, role: .radar, displayName: "Varia RTL515"),
    ]

    /// Seeded in the same dependency scope the store reads from — see `StartSheetFeatureTests`.
    private func makeStore(
        dependencies: @escaping (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<SensorHealthFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.pairedSensors = Self.paired }
            return TestStore(initialState: SensorHealthFeature.State()) {
                SensorHealthFeature()
            } withDependencies: {
                $0.defaultFileStorage = storage
                $0.date = .constant(Self.now)
                dependencies(&$0)
            }
        }
    }

    @Test("A role's battery lands on its paired device; both CSC roles of a combo share one entry")
    func batteryMapsToPeripheral() async {
        let store = makeStore()
        await store.send(.batteryReported(.speed, 87)) { $0.log.recordBattery(87, peripheral: Self.combo) }
        await store.send(.batteryReported(.cadence, 10)) { $0.log.recordBattery(10, peripheral: Self.combo) }
        await store.send(.batteryReported(.radar, 70)) { $0.log.recordBattery(70, peripheral: Self.radar) }

        let reports = store.state.log.reports(rideId: UUID(0))
        #expect(reports.count == 2)
        #expect(reports[Self.combo]?.minBatteryPercent == 10)
    }

    @Test("An unpaired role's battery and an unpaired peripheral's link loss are ignored")
    func unpairedIgnored() async {
        let store = makeStore()
        await store.send(.batteryReported(.heartRate, 5))
        await store.send(.linkTimedOut(Self.stranger))
        #expect(store.state.log.reports(rideId: UUID(0)).isEmpty)
    }

    @Test("A paired peripheral's link loss is recorded at the current time")
    func linkLossRecorded() async {
        let store = makeStore()
        await store.send(.linkTimedOut(Self.combo)) {
            $0.log.recordLinkLoss(peripheral: Self.combo, at: Self.now)
        }
    }

    @Test("Start listening subscribes to every battery stream and to link timeouts")
    func startListeningSubscribes() async {
        let (radarStream, radarContinuation) = AsyncStream<Int?>.makeStream()
        let (speedStream, speedContinuation) = AsyncStream<Int?>.makeStream()
        let (events, eventContinuation) = AsyncStream<BLEEvent>.makeStream()
        var radar = VariaRadarClient.testValue
        radar.batteryLevel = { radarStream }
        var csc = BLECSCClient.testValue
        csc.batteryLevel = { role in role == .speed ? speedStream : AsyncStream { $0.finish() } }
        var ble = BLEClient.testValue
        ble.events = { events }

        let store = makeStore {
            $0.variaRadarClient = radar
            $0.bleCSCClient = csc
            $0.bleClient = ble
        }
        await store.send(.startListening)

        radarContinuation.yield(64)
        await store.receive(.batteryReported(.radar, 64)) { $0.log.recordBattery(64, peripheral: Self.radar) }
        speedContinuation.yield(nil)
        await store.receive(.batteryReported(.speed, nil))
        eventContinuation.yield(.disconnected(id: Self.combo, error: CBError(.connectionTimeout)))
        await store.receive(.linkTimedOut(Self.combo)) {
            $0.log.recordLinkLoss(peripheral: Self.combo, at: Self.now)
        }

        radarContinuation.finish()
        speedContinuation.finish()
        eventContinuation.finish()
        await store.finish()
    }
}

@MainActor
@Suite("Ride end saves sensor health (#391)")
struct RideEndSensorHealthTests {
    static let combo = UUID(1)
    static let radar = UUID(2)
    static let earlierRide = UUID(7)
    static let rideId = UUID(8)

    @Test("Finishing writes each reporting device's verdict to all its records; a silent one keeps its last")
    func finishWritesReports() async {
        let storage = FileStorage.inMemory
        let staleRadarReport = SensorHealthReport(rideId: Self.earlierRide, minBatteryPercent: 4, maxLinkLossesPerWindow: 0)

        var state = withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock {
                $0.pairedSensors = [
                    PairedSensor(peripheralID: Self.combo, role: .speed, displayName: "Wahoo RPM"),
                    PairedSensor(peripheralID: Self.combo, role: .cadence, displayName: "Wahoo RPM"),
                    PairedSensor(peripheralID: Self.radar, role: .radar, displayName: "Varia RTL515",
                                 lastRideHealth: staleRadarReport),
                ]
            }
            return ActiveRideFeature.State(rideId: Self.rideId, recordingState: .paused)
        }
        // The combo sagged; the radar never connected this ride, so it reported nothing.
        for level in [87, nil, 10, nil, 95, nil, 0] {
            state.sensorHealth.log.recordBattery(level, peripheral: Self.combo)
        }

        let store = TestStore(initialState: state) {
            ActiveRideFeature()
        } withDependencies: {
            $0.defaultFileStorage = storage
            $0.continuousClock = TestClock()
            $0.date = .constant(Date(timeIntervalSince1970: 1_000_000))
            $0.hapticsClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.locationClient = .testValue
            $0.persistenceClient = .mock()
        }
        store.exhaustivity = .off

        await store.send(.finishTapped)
        await store.send(.finishAlert(.presented(.confirmFinish)))

        let sensors = store.state.preferences.pairedSensors
        let expected = SensorHealthReport(rideId: Self.rideId, minBatteryPercent: 0, maxLinkLossesPerWindow: 0)
        #expect(sensors[0].lastRideHealth == expected)
        #expect(sensors[1].lastRideHealth == expected)
        // A dead cell that never connects must not have its warning cleared by a ride it sat out.
        #expect(sensors[2].lastRideHealth == staleRadarReport)
    }
}
