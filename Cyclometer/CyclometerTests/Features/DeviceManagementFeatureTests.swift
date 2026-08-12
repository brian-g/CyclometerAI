import Testing
import Foundation
import ComposableArchitecture
@testable import Cyclometer

@MainActor
@Suite("DeviceManagementFeature")
struct DeviceManagementFeatureTests {

    private static let pairedID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    private static let availableID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!

    private static let combo = BLECSCClient.Capabilities(
        supportsWheelRevolutions: true, supportsCrankRevolutions: true
    )
    private static let wheelOnly = BLECSCClient.Capabilities(
        supportsWheelRevolutions: true, supportsCrankRevolutions: false
    )
    private static let crankOnly = BLECSCClient.Capabilities(
        supportsWheelRevolutions: false, supportsCrankRevolutions: true
    )

    private static func sensor(
        id: UUID,
        name: String?,
        roles: Set<BLECSCClient.SensorRole> = [],
        state: BLECSCClient.ConnectionState? = nil,
        battery: Int? = nil,
        capabilities: BLECSCClient.Capabilities? = nil
    ) -> BLECSCClient.DiscoveredSensor {
        .init(
            id: id, name: name, roles: roles, connectionState: state,
            batteryPercent: battery, capabilities: capabilities
        )
    }

    /// The dialog literal, rebuilt here rather than reached through the reducer's
    /// private builder — the same convention `ActiveRideFeatureTests` uses for
    /// `finishAlert`, so a copy change has to be made deliberately in both places.
    private static func expectedDialog(
        for id: UUID, name: String?
    ) -> ConfirmationDialogState<DeviceManagementFeature.Action.RoleChoice> {
        ConfirmationDialogState {
            TextState("What should this sensor do?")
        } actions: {
            ButtonState(action: .chose(peripheralID: id, roles: [.speed])) { TextState("Speed") }
            ButtonState(action: .chose(peripheralID: id, roles: [.cadence])) { TextState("Cadence") }
            ButtonState(action: .chose(peripheralID: id, roles: [.speed, .cadence])) { TextState("Both") }
            ButtonState(role: .cancel) { TextState("Cancel") }
        } message: {
            TextState("\(name ?? "This sensor") reports both wheel and crank data.")
        }
    }

    /// Each store gets its own in-memory file system so persisted pairings cannot
    /// leak between tests. Seeding happens inside the same scope, otherwise the seed
    /// and the store would read different storage — same idiom as SettingsFeatureTests.
    private func makeStore(
        devices: [BLECSCClient.DiscoveredSensor] = [],
        pairedSensors: [PairedSensor] = [],
        bleCSCClient: BLECSCClient = .testValue
    ) -> TestStoreOf<DeviceManagementFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.pairedSensors = pairedSensors }
            return TestStore(
                initialState: DeviceManagementFeature.State(devices: devices)
            ) {
                DeviceManagementFeature()
            } withDependencies: {
                $0.bleCSCClient = bleCSCClient
                $0.defaultFileStorage = storage
            }
        }
    }

    // MARK: Scanning

    @Test("Appearing starts a pairing scan and pipes the device stream into state")
    func taskStartsScanAndSubscribes() async {
        let (stream, continuation) = AsyncStream<[BLECSCClient.DiscoveredSensor]>.makeStream()
        let scansStarted = LockIsolated(0)
        var ble = BLECSCClient.testValue
        ble.beginPairingScan = { scansStarted.withValue { $0 += 1 } }
        ble.discoveredSensors = { stream }

        let store = makeStore(bleCSCClient: ble)
        await store.send(.task)
        #expect(scansStarted.value == 1)

        let found = [Self.sensor(id: Self.availableID, name: "GSC-10")]
        continuation.yield(found)
        await store.receive(\.devicesUpdated) {
            $0.devices = found
        }

        continuation.finish()
        await store.finish()
    }

    @Test("Leaving the screen ends the pairing scan")
    func onDisappearEndsScan() async {
        let scansEnded = LockIsolated(0)
        var ble = BLECSCClient.testValue
        ble.endPairingScan = { scansEnded.withValue { $0 += 1 } }

        let store = makeStore(bleCSCClient: ble)
        await store.send(.onDisappear)
        await store.finish()

        #expect(scansEnded.value == 1)
    }

    // MARK: Pairing and role selection

    @Test("Pair connects for interrogation and records the pairing as in flight")
    func pairStartsInterrogation() async {
        let paired = LockIsolated<[UUID]>([])
        var ble = BLECSCClient.testValue
        ble.pair = { id in paired.withValue { $0.append(id) } }

        let store = makeStore(bleCSCClient: ble)
        await store.send(.pairButtonTapped(Self.availableID)) {
            $0.pendingPairing = Self.availableID
        }
        await store.finish()

        #expect(paired.value == [Self.availableID])
    }

    @Test("A combo sensor's capabilities raise the role prompt")
    func comboCapabilitiesPromptForRole() async {
        let store = makeStore()
        await store.send(.pairButtonTapped(Self.availableID)) {
            $0.pendingPairing = Self.availableID
        }

        let found = [Self.sensor(id: Self.availableID, name: "Wahoo RPM", capabilities: Self.combo)]
        await store.send(.devicesUpdated(found)) {
            $0.devices = found
            $0.roleDialog = Self.expectedDialog(for: Self.availableID, name: "Wahoo RPM")
        }
        await store.finish()
    }

    @Test(
        "A single-capability sensor is assigned without a prompt",
        arguments: [
            (BLECSCClient.Capabilities(supportsWheelRevolutions: true, supportsCrankRevolutions: false),
             BLECSCClient.SensorRole.speed),
            (BLECSCClient.Capabilities(supportsWheelRevolutions: false, supportsCrankRevolutions: true),
             BLECSCClient.SensorRole.cadence)
        ]
    )
    func singleCapabilityAutoAssigns(
        capabilities: BLECSCClient.Capabilities, expected: BLECSCClient.SensorRole
    ) async {
        let assigned = LockIsolated<[(UUID, Set<BLECSCClient.SensorRole>)]>([])
        var ble = BLECSCClient.testValue
        ble.setRoles = { id, roles in assigned.withValue { $0.append((id, roles)) } }

        let store = makeStore(bleCSCClient: ble)
        await store.send(.pairButtonTapped(Self.availableID)) {
            $0.pendingPairing = Self.availableID
        }

        let found = [Self.sensor(id: Self.availableID, name: "GSC-10", capabilities: capabilities)]
        await store.send(.devicesUpdated(found)) {
            $0.devices = found
            $0.pendingPairing = nil
            $0.$preferences.withLock {
                $0.pairedSensors = [
                    PairedSensor(peripheralID: Self.availableID, role: expected, displayName: "GSC-10")
                ]
            }
        }
        await store.finish()

        #expect(assigned.value.count == 1)
        #expect(assigned.value[0].0 == Self.availableID)
        #expect(assigned.value[0].1 == [expected])
        // No prompt: nothing to ask about.
        #expect(store.state.roleDialog == nil)
    }

    @Test("Choosing Both persists two records and pushes them to the client")
    func choosingBothPersistsAndPushes() async {
        let assigned = LockIsolated<[(UUID, Set<BLECSCClient.SensorRole>)]>([])
        let pushed = LockIsolated<[[UUID: Set<BLECSCClient.SensorRole>]]>([])
        var ble = BLECSCClient.testValue
        ble.setRoles = { id, roles in assigned.withValue { $0.append((id, roles)) } }
        ble.setPairedSensors = { map in pushed.withValue { $0.append(map) } }

        let found = [Self.sensor(id: Self.availableID, name: "Wahoo RPM", capabilities: Self.combo)]
        let store = makeStore(bleCSCClient: ble)
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.pairButtonTapped(Self.availableID))
        // The capabilities arriving is what raises the prompt; sending the choice
        // without it would be a presentation action with no presented state.
        await store.send(.devicesUpdated(found))
        #expect(store.state.roleDialog != nil)
        await store.send(.roleDialog(.presented(.chose(peripheralID: Self.availableID, roles: [.speed, .cadence]))))
        await store.finish()

        // Declaration order, not Set order — the persisted file must not churn.
        #expect(store.state.preferences.pairedSensors == [
            PairedSensor(peripheralID: Self.availableID, role: .speed, displayName: "Wahoo RPM"),
            PairedSensor(peripheralID: Self.availableID, role: .cadence, displayName: "Wahoo RPM")
        ])
        #expect(assigned.value.map(\.1) == [[.speed, .cadence]])
        #expect(pushed.value == [[Self.availableID: [.speed, .cadence]]])
        #expect(store.state.pendingPairing == nil)
    }

    @Test("Cancelling the prompt during a new pairing releases the sensor")
    func cancellingNewPairingUnpairs() async {
        let unpaired = LockIsolated<[UUID]>([])
        var ble = BLECSCClient.testValue
        ble.unpair = { id in unpaired.withValue { $0.append(id) } }

        let found = [Self.sensor(id: Self.availableID, name: "Wahoo RPM", capabilities: Self.combo)]
        let store = makeStore(bleCSCClient: ble)
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.pairButtonTapped(Self.availableID))
        await store.send(.devicesUpdated(found))
        await store.send(.roleDialog(.dismiss))
        await store.finish()

        #expect(unpaired.value == [Self.availableID])
        #expect(store.state.preferences.pairedSensors.isEmpty)
    }

    @Test("Cancelling a reassignment leaves the existing pairing alone")
    func cancellingReassignmentKeepsPairing() async {
        let unpaired = LockIsolated<[UUID]>([])
        var ble = BLECSCClient.testValue
        ble.unpair = { id in unpaired.withValue { $0.append(id) } }

        let existing = [PairedSensor(peripheralID: Self.pairedID, role: .speed, displayName: "Wahoo RPM")]
        let store = makeStore(
            devices: [Self.sensor(id: Self.pairedID, name: "Wahoo RPM", roles: [.speed],
                                  state: .active, capabilities: Self.combo)],
            pairedSensors: existing,
            bleCSCClient: ble
        )
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.rowTapped(Self.pairedID))
        #expect(store.state.roleDialog != nil)
        await store.send(.roleDialog(.dismiss))
        await store.finish()

        #expect(unpaired.value.isEmpty)
        #expect(store.state.preferences.pairedSensors == existing)
    }

    // MARK: Reassignment

    @Test("Tapping a paired combo sensor re-opens the prompt; Cadence releases Speed")
    func reassignmentReleasesTheOtherRole() async {
        let assigned = LockIsolated<[(UUID, Set<BLECSCClient.SensorRole>)]>([])
        var ble = BLECSCClient.testValue
        ble.setRoles = { id, roles in assigned.withValue { $0.append((id, roles)) } }

        let store = makeStore(
            devices: [Self.sensor(id: Self.pairedID, name: "Wahoo RPM", roles: [.speed, .cadence],
                                  state: .active, capabilities: Self.combo)],
            pairedSensors: [
                PairedSensor(peripheralID: Self.pairedID, role: .speed, displayName: "Wahoo RPM"),
                PairedSensor(peripheralID: Self.pairedID, role: .cadence, displayName: "Wahoo RPM")
            ],
            bleCSCClient: ble
        )
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.rowTapped(Self.pairedID))
        await store.send(.roleDialog(.presented(.chose(peripheralID: Self.pairedID, roles: [.cadence]))))
        await store.finish()

        #expect(store.state.preferences.pairedSensors == [
            PairedSensor(peripheralID: Self.pairedID, role: .cadence, displayName: "Wahoo RPM")
        ])
        #expect(assigned.value.map(\.1) == [[.cadence]])
    }

    @Test("A sensor that can only do one thing is not re-promptable")
    func singleCapabilitySensorIsNotReassignable() async {
        let store = makeStore(
            devices: [Self.sensor(id: Self.pairedID, name: "GSC-10", roles: [.speed],
                                  state: .active, capabilities: Self.wheelOnly)],
            pairedSensors: [PairedSensor(peripheralID: Self.pairedID, role: .speed, displayName: "GSC-10")]
        )
        #expect(store.state.reassignableIDs.isEmpty)

        await store.send(.rowTapped(Self.pairedID))
        #expect(store.state.roleDialog == nil)
    }

    @Test("Assigning a role to a second sensor takes it off the first")
    func roleMovesBetweenSensors() async {
        let found = [
            Self.sensor(id: Self.pairedID, name: "Wahoo RPM", roles: [.speed],
                        state: .active, capabilities: Self.wheelOnly),
            Self.sensor(id: Self.availableID, name: "GSC-10", capabilities: Self.combo)
        ]
        let store = makeStore(
            pairedSensors: [PairedSensor(peripheralID: Self.pairedID, role: .speed, displayName: "Wahoo RPM")]
        )
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.pairButtonTapped(Self.availableID))
        await store.send(.devicesUpdated(found))
        await store.send(.roleDialog(.presented(.chose(peripheralID: Self.availableID, roles: [.speed]))))
        await store.finish()

        // The incumbent's speed record is gone — one sensor per role, app-wide.
        #expect(store.state.preferences.pairedSensors == [
            PairedSensor(peripheralID: Self.availableID, role: .speed, displayName: "GSC-10")
        ])
    }

    // MARK: Sections and unpairing

    @Test("Sections come from the persisted records, not from live role state")
    func sectionsComeFromPersistedRecords() {
        let store = makeStore(
            devices: [
                Self.sensor(id: Self.pairedID, name: "Wahoo RPM", roles: [.speed, .cadence], state: .active),
                Self.sensor(id: Self.availableID, name: "GSC-10")
            ],
            pairedSensors: [PairedSensor(peripheralID: Self.pairedID, role: .speed, displayName: "Wahoo RPM")]
        )

        #expect(store.state.pairedDevices.map(\.id) == [Self.pairedID])
        #expect(store.state.availableDevices.map(\.id) == [Self.availableID])
    }

    /// The case `DiscoveredSensor.isPaired` cannot express: the sensor is paired but
    /// out of range, so it holds no roles in the client. It must still appear under
    /// Paired — with a Disconnected subtitle — or the rider cannot unpair it.
    @Test("A paired sensor that is out of range still shows as paired")
    func outOfRangePairedSensorStillListed() {
        let store = makeStore(
            devices: [],
            pairedSensors: [PairedSensor(peripheralID: Self.pairedID, role: .speed, displayName: "Wahoo RPM")]
        )

        #expect(store.state.pairedDevices.map(\.id) == [Self.pairedID])
        #expect(store.state.pairedDevices.first?.name == "Wahoo RPM")
        #expect(store.state.pairedDevices.first?.connectionState == .disconnected)
        #expect(store.state.availableDevices.isEmpty)
    }

    @Test("Unpairing drops the records and pushes the reduced set to the client")
    func unpairDropsRecordsAndPushes() async {
        let unpaired = LockIsolated<[UUID]>([])
        let pushed = LockIsolated<[[UUID: Set<BLECSCClient.SensorRole>]]>([])
        var ble = BLECSCClient.testValue
        ble.unpair = { id in unpaired.withValue { $0.append(id) } }
        ble.setPairedSensors = { map in pushed.withValue { $0.append(map) } }

        let store = makeStore(
            devices: [Self.sensor(id: Self.pairedID, name: "Wahoo RPM", roles: [.speed], state: .active)],
            pairedSensors: [PairedSensor(peripheralID: Self.pairedID, role: .speed, displayName: "Wahoo RPM")],
            bleCSCClient: ble
        )
        await store.send(.unpairButtonTapped(Self.pairedID)) {
            $0.$preferences.withLock { $0.pairedSensors = [] }
        }
        await store.finish()

        #expect(unpaired.value == [Self.pairedID])
        #expect(pushed.value == [[:]])
        // The row survives as an Available device so it can be paired again.
        #expect(store.state.availableDevices.map(\.id) == [Self.pairedID])
    }
}
