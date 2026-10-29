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
        paired: [PairedSensor]? = nil,
        dependencies: @escaping (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<SensorHealthFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.pairedSensors = paired ?? Self.paired }
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
        await store.send(.statusChanged(.radar, isConnected: true)) {
            $0.connectedRoles = [.radar]
            $0.log.recordConnected(peripheral: Self.radar)
        }
        #expect(store.state.log.reports(rideId: UUID(0)) == [
            Self.radar: SensorHealthReport(rideId: UUID(0), minBatteryPercent: nil, maxLinkLossesPerWindow: 0)
        ])
        // An unpaired role connecting says nothing about any paired device.
        await store.send(.statusChanged(.heartRate, isConnected: true)) { $0.connectedRoles = [.radar, .heartRate] }
        #expect(store.state.log.reports(rideId: UUID(0)).count == 1)
    }

    // MARK: Live status (#464, #466)

    @Test("A paired sensor never found this ride is missing; one row per device, a combo once")
    func neverFoundIsMissing() async {
        let store = makeStore()
        #expect(store.state.devices.map(\.title) == ["Radar", "Speed & Cadence"])
        #expect(store.state.devices.map(\.name) == ["Varia RTL515", "Wahoo RPM"])
        #expect(store.state.devicesNeedingAttention.map(\.id) == [Self.radar, Self.combo])
        #expect(store.state.devices.allSatisfy { $0.isMissing })
    }

    @Test("With nothing paired, nothing needs attention, whatever the clients say")
    func nothingPaired() async {
        let store = makeStore(paired: [])
        await store.send(.statusChanged(.radar, isConnected: true)) { $0.connectedRoles = [.radar] }
        await store.send(.batteryReported(.radar, 5))
        #expect(store.state.devices.isEmpty)
        #expect(store.state.devicesNeedingAttention.isEmpty)
    }

    @Test("A combo CSC sensor is connected only once both its roles are, and reads its lower level")
    func comboCountsOnce() async {
        let store = makeStore()
        await store.send(.statusChanged(.speed, isConnected: true)) {
            $0.connectedRoles = [.speed]
            $0.log.recordConnected(peripheral: Self.combo)
        }
        #expect(store.state.devices.first { $0.id == Self.combo }?.isMissing == true)

        await store.send(.statusChanged(.cadence, isConnected: true)) { $0.connectedRoles = [.speed, .cadence] }
        await store.send(.batteryReported(.speed, 60)) {
            $0.log.recordBattery(60, peripheral: Self.combo)
        }
        await store.send(.batteryReported(.cadence, 40)) {
            $0.log.recordBattery(40, peripheral: Self.combo)
        }
        let combo = store.state.devices.first { $0.id == Self.combo }
        #expect(combo?.isConnected == true)
        #expect(combo?.batteryPercent == 40)
        // The radar is still missing; the combo, up and healthy, no longer counts.
        #expect(store.state.devicesNeedingAttention.map(\.id) == [Self.radar])
    }

    @Test("A connected sensor that reads 20% or less is low for the rest of the ride, whatever it reads after")
    func lowBatteryLatches() async {
        let store = makeStore(paired: [Self.paired[2]])
        await store.send(.statusChanged(.radar, isConnected: true)) {
            $0.connectedRoles = [.radar]
            $0.log.recordConnected(peripheral: Self.radar)
        }
        await store.send(.batteryReported(.radar, 21)) { $0.log.recordBattery(21, peripheral: Self.radar) }
        #expect(store.state.devicesNeedingAttention.isEmpty)

        await store.send(.batteryReported(.radar, 20)) { $0.log.recordBattery(20, peripheral: Self.radar) }
        #expect(store.state.devicesNeedingAttention.map(\.isBatteryLow) == [true])

        // A sagging cell reads high again between transmissions (BLE.md §14.5): the button stays, at
        // the level that tripped it, rather than flicking off and on as the cell rebounds.
        await store.send(.batteryReported(.radar, 95))
        await store.send(.batteryReported(.radar, 21))
        #expect(store.state.devicesNeedingAttention.map(\.batteryPercent) == [20])
    }

    @Test("A low sensor that drops counts as missing, not low; reconnected, it is low again")
    func lowThenDisconnected() async {
        let store = makeStore(paired: [Self.paired[2]])
        await store.send(.statusChanged(.radar, isConnected: true)) {
            $0.connectedRoles = [.radar]
            $0.log.recordConnected(peripheral: Self.radar)
        }
        await store.send(.batteryReported(.radar, 18)) { $0.log.recordBattery(18, peripheral: Self.radar) }
        await store.send(.statusChanged(.radar, isConnected: false)) { $0.connectedRoles = [] }
        // The client's nil on disconnect means unknown, and leaves the ride's minimum alone.
        await store.send(.batteryReported(.radar, nil))
        let dropped = store.state.devices.first
        #expect(dropped?.isMissing == true)
        #expect(dropped?.isBatteryLow == false)
        #expect(store.state.devicesNeedingAttention.count == 1)

        await store.send(.statusChanged(.radar, isConnected: true)) { $0.connectedRoles = [.radar] }
        await store.send(.batteryReported(.radar, 90))
        #expect(store.state.devices.first?.isBatteryLow == true)
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
        await store.receive(.statusChanged(.radar, isConnected: false))
        radarStateContinuation.yield(.active)
        await store.receive(.statusChanged(.radar, isConnected: true)) {
            $0.connectedRoles = [.radar]
            $0.log.recordConnected(peripheral: Self.radar)
        }
        radarContinuation.yield(64)
        await store.receive(.batteryReported(.radar, 64)) {
            $0.log.recordBattery(64, peripheral: Self.radar)
        }
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

@MainActor
@Suite("Sensors button VoiceOver (#464, #466)")
struct SensorsButtonAccessibilityTests {
    @Test("Missing sensors are counted, as #466 words it")
    func missing() {
        #expect(SensorsButton.accessibilityLabel(for: [.sampleRadarMissing]) == "Sensors, 1 not found")
        #expect(SensorsButton.accessibilityLabel(for: [.sampleRadarMissing, .sampleComboMissing]) == "Sensors, 2 not found")
    }

    @Test("Low sensors are named with their level, as #464 words it")
    func low() {
        #expect(SensorsButton.accessibilityLabel(for: [.sampleRadarLow]) == "Sensors, low battery: Radar, 18 percent")
        #expect(SensorsButton.accessibilityLabel(for: [.sampleRadarLow, .sampleHeartRateLow])
                == "Sensors, low battery: Radar, 18 percent, Heart Rate, 9 percent")
    }

    @Test("Missing and low together read both")
    func both() {
        #expect(SensorsButton.accessibilityLabel(for: [.sampleComboMissing, .sampleHeartRateLow])
                == "Sensors, 1 not found, low battery: Heart Rate, 9 percent")
    }
}

@MainActor
@Suite("Ride Sensors sheet (#464, #466)")
struct RideSensorsSheetTests {
    @Test("The Sensors button opens the sheet, and the sheet's dismissal closes it, with nothing else sent")
    func buttonOpensSheet() async {
        let storage = FileStorage.inMemory
        let store = withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            TestStore(initialState: ActiveRideFeature.State(recordingState: .active)) {
                ActiveRideFeature()
            } withDependencies: {
                $0.defaultFileStorage = storage
            }
        }

        // Exhaustive: no haptic, sound or banner effect rides along with either.
        await store.send(.sensorsButtonTapped) { $0.isSensorsSheetPresented = true }
        await store.send(.sensorsSheetPresentationChanged(false)) { $0.isSensorsSheetPresented = false }
    }

    /// SwiftUI won't show the finish alert from a dashboard already showing a sheet, and auto-end
    /// fires only once — as `autoEndClosesPicker` pins for the Add Widget sheet (#142 review).
    @Test("Auto-end closes the Sensors sheet so its finish alert can show")
    func autoEndClosesSensorsSheet() async {
        let storage = FileStorage.inMemory
        let store = withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            TestStore(initialState: ActiveRideFeature.State(recordingState: .active)) {
                ActiveRideFeature()
            } withDependencies: {
                $0.defaultFileStorage = storage
            }
        }

        await store.send(.sensorsButtonTapped) { $0.isSensorsSheetPresented = true }
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.autoEndTriggered)
        await store.receive(\.finishTapped) {
            $0.isSensorsSheetPresented = false
        }
        #expect(store.state.finishAlert != nil)
    }
}
