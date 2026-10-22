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
    /// Recording by default: link losses only count while the ride records.
    private func makeStore(
        isRecording: Bool = true,
        dependencies: @escaping (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<SensorHealthFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.pairedSensors = Self.paired }
            return TestStore(initialState: SensorHealthFeature.State(isRecording: isRecording)) {
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

    @Test("A link loss while paused doesn't count — the rider may have walked off with the phone")
    func pausedLinkLossIgnored() async {
        let store = makeStore(isRecording: false)
        await store.send(.linkTimedOut(Self.combo))
        #expect(store.state.log.reports(rideId: UUID(0)).isEmpty)
    }

    @Test("Connecting is enough for a verdict, so a sensor without battery reporting gets one")
    func connectedRecordsPresence() async {
        let store = makeStore()
        await store.send(.connected(.radar)) { $0.log.recordConnected(peripheral: Self.radar) }
        #expect(store.state.log.reports(rideId: UUID(0)) == [
            Self.radar: SensorHealthReport(rideId: UUID(0), minBatteryPercent: nil, maxLinkLossesPerWindow: 0)
        ])
        // An unpaired role connecting says nothing about any paired device.
        await store.send(.connected(.heartRate))
    }

    @Test("Start listening subscribes to every battery stream and to link timeouts")
    func startListeningSubscribes() async {
        let (radarStream, radarContinuation) = AsyncStream<Int?>.makeStream()
        let (speedStream, speedContinuation) = AsyncStream<Int?>.makeStream()
        let (events, eventContinuation) = AsyncStream<BLEEvent>.makeStream()
        let (radarState, radarStateContinuation) = AsyncStream<SensorConnectionState>.makeStream()
        var radar = VariaRadarClient.testValue
        radar.batteryLevel = { radarStream }
        radar.connectionState = { radarState }
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

        // Only `.active` counts as showing up.
        radarStateContinuation.yield(.connecting)
        radarStateContinuation.yield(.active)
        await store.receive(.connected(.radar)) { $0.log.recordConnected(peripheral: Self.radar) }
        radarContinuation.yield(64)
        await store.receive(.batteryReported(.radar, 64)) { $0.log.recordBattery(64, peripheral: Self.radar) }
        speedContinuation.yield(nil)
        await store.receive(.batteryReported(.speed, nil))
        eventContinuation.yield(.disconnected(id: Self.combo, error: CBError(.connectionTimeout)))
        await store.receive(.linkTimedOut(Self.combo)) {
            $0.log.recordLinkLoss(peripheral: Self.combo, at: Self.now)
        }

        radarContinuation.finish()
        radarStateContinuation.finish()
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

    @Test("Finishing saves each device that showed up; one that didn't keeps its last verdict")
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
                    PairedSensor(peripheralID: Self.radar, role: .radar, displayName: "Varia RTL515"),
                ]
                $0.sensorHealth = [Self.radar: staleRadarReport]
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

        #expect(store.state.preferences.sensorHealth == [
            Self.combo: SensorHealthReport(rideId: Self.rideId, minBatteryPercent: 0, maxLinkLossesPerWindow: 0),
            // A dead cell that never connects must not have its warning cleared by a ride it sat out.
            Self.radar: staleRadarReport,
        ])
    }

    @Test("The link-loss count follows the ride's recording state")
    func recordingStateForwarded() async {
        let store = TestStore(initialState: ActiveRideFeature.State(recordingState: .active)) {
            ActiveRideFeature()
        } withDependencies: {
            $0.defaultFileStorage = .inMemory
            $0.continuousClock = TestClock()
            $0.date = .constant(Date(timeIntervalSince1970: 1_000_000))
            $0.hapticsClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.locationClient = .testValue
            $0.persistenceClient = .mock()
        }
        store.exhaustivity = .off

        await store.send(.pauseTapped)
        #expect(!store.state.sensorHealth.isRecording)
        await store.send(.resumeTapped)
        #expect(store.state.sensorHealth.isRecording)
    }
}
