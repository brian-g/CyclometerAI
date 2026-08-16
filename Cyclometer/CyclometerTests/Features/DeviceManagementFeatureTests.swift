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
        roles: Set<SensorRole> = [],
        state: BLECSCClient.ConnectionState? = nil,
        battery: Int? = nil,
        capabilities: BLECSCClient.Capabilities? = nil
    ) -> BLECSCClient.DiscoveredSensor {
        .init(
            id: id, name: name, roles: roles, connectionState: state,
            batteryPercent: battery, capabilities: capabilities
        )
    }

    /// One log across all three write endpoints. The ordering *between* them is the
    /// thing under test — a separate `LockIsolated` per endpoint can only show that
    /// each was called, which is what let two ordering races through review.
    private enum ClientCall: Equatable {
        case setPairedSensors([UUID: Set<SensorRole>])
        case setRoles(UUID, Set<SensorRole>)
        case unpair(UUID)
    }

    private static func recordingClient(into log: LockIsolated<[ClientCall]>) -> BLECSCClient {
        var ble = BLECSCClient.testValue
        ble.setPairedSensors = { map in log.withValue { $0.append(.setPairedSensors(map)) } }
        ble.setRoles = { id, roles in log.withValue { $0.append(.setRoles(id, roles)) } }
        ble.unpair = { id in log.withValue { $0.append(.unpair(id)) } }
        return ble
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
             SensorRole.speed),
            (BLECSCClient.Capabilities(supportsWheelRevolutions: false, supportsCrankRevolutions: true),
             SensorRole.cadence)
        ]
    )
    func singleCapabilityAutoAssigns(
        capabilities: BLECSCClient.Capabilities, expected: SensorRole
    ) async {
        let assigned = LockIsolated<[(UUID, Set<SensorRole>)]>([])
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
        let assigned = LockIsolated<[(UUID, Set<SensorRole>)]>([])
        let pushed = LockIsolated<[[UUID: Set<SensorRole>]]>([])
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
        let assigned = LockIsolated<[(UUID, Set<SensorRole>)]>([])
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
        let pushed = LockIsolated<[[UUID: Set<SensorRole>]]>([])
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

    // MARK: Write ordering
    //
    // `pairedAssignments` inside the client is the gate `.discovered` consults before
    // reconnecting anything, and the client drops its lock across every connect and
    // disconnect. So a teardown that runs before the narrowed map is pushed leaves a
    // window — roughly one advertising interval, with the pairing scan running — in
    // which the sensor's own advertisement undoes the rider's action.

    @Test("Unpair closes the reconnect gate before releasing the connection")
    func unpairPushesAssignmentsFirst() async {
        let log = LockIsolated<[ClientCall]>([])
        let store = makeStore(
            devices: [Self.sensor(id: Self.pairedID, name: "Wahoo RPM", roles: [.speed], state: .active)],
            pairedSensors: [PairedSensor(peripheralID: Self.pairedID, role: .speed, displayName: "Wahoo RPM")],
            bleCSCClient: Self.recordingClient(into: log)
        )
        await store.send(.unpairButtonTapped(Self.pairedID)) {
            $0.$preferences.withLock { $0.pairedSensors = [] }
        }
        await store.finish()

        // The other order reconnects the sensor holding the role it was just denied,
        // with no record left behind it.
        #expect(log.value == [.setPairedSensors([:]), .unpair(Self.pairedID)])
    }

    @Test("A reassignment pushes the new assignments before moving the role")
    func reassignmentPushesAssignmentsFirst() async {
        let log = LockIsolated<[ClientCall]>([])
        let found = [
            Self.sensor(id: Self.pairedID, name: "GSC-10", roles: [.speed],
                        state: .active, capabilities: Self.wheelOnly),
            Self.sensor(id: Self.availableID, name: "Wahoo RPM", capabilities: Self.combo)
        ]
        let store = makeStore(
            pairedSensors: [PairedSensor(peripheralID: Self.pairedID, role: .speed, displayName: "GSC-10")],
            bleCSCClient: Self.recordingClient(into: log)
        )
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.pairButtonTapped(Self.availableID))
        await store.send(.devicesUpdated(found))
        await store.send(.roleDialog(.presented(.chose(peripheralID: Self.availableID, roles: [.speed]))))
        await store.finish()

        // `setRoles` strips the incumbent's last role and disconnects it. Pushing
        // after that would let its next advertisement reconnect it under the old map
        // and take speed straight back off the sensor the rider chose.
        #expect(log.value == [
            .setPairedSensors([Self.availableID: [.speed]]),
            .setRoles(Self.availableID, [.speed])
        ])
    }

    // MARK: Capability reconciliation

    /// The rider cannot produce this state — the prompt only offers roles the
    /// capabilities advertise — but a pairing can outlive a firmware change. The
    /// client narrows its own slot either way; the record has to follow, or every
    /// launch reconnects, re-narrows, and the paired row keeps claiming the role.
    @Test("A role the hardware no longer supports is dropped from the record")
    func narrowedCapabilitiesCorrectTheRecord() async {
        let log = LockIsolated<[ClientCall]>([])
        let store = makeStore(
            pairedSensors: [
                PairedSensor(peripheralID: Self.pairedID, role: .speed, displayName: "Wahoo RPM"),
                PairedSensor(peripheralID: Self.pairedID, role: .cadence, displayName: "Wahoo RPM")
            ],
            bleCSCClient: Self.recordingClient(into: log)
        )

        let found = [Self.sensor(id: Self.pairedID, name: "Wahoo RPM", roles: [.speed],
                                 state: .active, capabilities: Self.wheelOnly)]
        await store.send(.devicesUpdated(found)) {
            $0.devices = found
            $0.$preferences.withLock {
                $0.pairedSensors = [
                    PairedSensor(peripheralID: Self.pairedID, role: .speed, displayName: "Wahoo RPM")
                ]
            }
        }
        await store.finish()

        #expect(log.value == [.setPairedSensors([Self.pairedID: [.speed]])])
    }

    @Test("A sensor that can no longer fill its only role is released outright")
    func narrowingToNothingUnpairs() async {
        let log = LockIsolated<[ClientCall]>([])
        let store = makeStore(
            pairedSensors: [PairedSensor(peripheralID: Self.pairedID, role: .cadence, displayName: "GSC-10")],
            bleCSCClient: Self.recordingClient(into: log)
        )

        let found = [Self.sensor(id: Self.pairedID, name: "GSC-10", capabilities: Self.wheelOnly)]
        await store.send(.devicesUpdated(found)) {
            $0.devices = found
            $0.$preferences.withLock { $0.pairedSensors = [] }
        }
        await store.finish()

        // `setRoles` rejects an empty set, so nothing left to hold has to go through
        // `unpair` — and the push still comes first.
        #expect(log.value == [.setPairedSensors([:]), .unpair(Self.pairedID)])
        #expect(store.state.pairedDevices.isEmpty)
    }

    @Test("Reconciliation is silent when nothing contradicts the record")
    func reconciliationIsSilentWithoutAContradiction() async {
        let log = LockIsolated<[ClientCall]>([])
        let records = [
            PairedSensor(peripheralID: Self.pairedID, role: .speed, displayName: "Wahoo RPM"),
            PairedSensor(peripheralID: Self.availableID, role: .cadence, displayName: "GSC-10")
        ]
        let store = makeStore(pairedSensors: records, bleCSCClient: Self.recordingClient(into: log))

        let found = [
            // Holds one of the two roles it advertises — what choosing Speed at the
            // prompt looks like, not a contradiction.
            Self.sensor(id: Self.pairedID, name: "Wahoo RPM", roles: [.speed],
                        state: .active, capabilities: Self.combo),
            // Never answered the 0x2A5C read. Silence is not evidence it cannot do
            // cadence, so the record stands.
            Self.sensor(id: Self.availableID, name: "GSC-10", roles: [.cadence], state: .active)
        ]
        await store.send(.devicesUpdated(found)) { $0.devices = found }
        await store.finish()

        #expect(log.value.isEmpty)
        #expect(store.state.preferences.pairedSensors == records)
    }

    @Test("Reconciliation does not disturb a pairing in flight")
    func reconciliationLeavesPendingPairingAlone() async {
        let log = LockIsolated<[ClientCall]>([])
        let store = makeStore(
            pairedSensors: [
                PairedSensor(peripheralID: Self.pairedID, role: .speed, displayName: "Wahoo RPM"),
                PairedSensor(peripheralID: Self.pairedID, role: .cadence, displayName: "Wahoo RPM")
            ],
            bleCSCClient: Self.recordingClient(into: log)
        )
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.pairButtonTapped(Self.availableID))

        // One broadcast carrying both a correction for the incumbent and the answer
        // the pairing is waiting on.
        let found = [
            Self.sensor(id: Self.pairedID, name: "Wahoo RPM", roles: [.speed],
                        state: .active, capabilities: Self.wheelOnly),
            Self.sensor(id: Self.availableID, name: "GSC-10", capabilities: Self.crankOnly)
        ]
        await store.send(.devicesUpdated(found))
        await store.finish()

        // Both ran, and the assignment map built last is the one that landed last.
        #expect(store.state.preferences.pairedSensors == [
            PairedSensor(peripheralID: Self.pairedID, role: .speed, displayName: "Wahoo RPM"),
            PairedSensor(peripheralID: Self.availableID, role: .cadence, displayName: "GSC-10")
        ])
        #expect(log.value == [
            .setPairedSensors([Self.pairedID: [.speed]]),
            .setPairedSensors([Self.pairedID: [.speed], Self.availableID: [.cadence]]),
            .setRoles(Self.availableID, [.cadence])
        ])
        #expect(store.state.pendingPairing == nil)
    }

    // MARK: Peripherals serving more than one profile

    // `PairedSensor` is one collection across every role (#93), but this screen only
    // speaks CSC until #98 unifies discovery. A device that also advertises radar or
    // heart rate therefore has records here that none of these actions may touch.
    // Every case below fails against a predicate keyed on `peripheralID` alone.

    /// The radar record shares a UUID with the CSC sensor, so a `peripheralID`-keyed
    /// removal deletes a pairing the rider made on a different screen.
    @Test("Assigning a CSC role leaves the same peripheral's radar record alone")
    func applyKeepsNonCSCRecordsForTheSamePeripheral() async {
        let pushed = LockIsolated<[[UUID: Set<SensorRole>]]>([])
        var ble = BLECSCClient.testValue
        ble.setPairedSensors = { map in pushed.withValue { $0.append(map) } }

        let found = [Self.sensor(id: Self.pairedID, name: "Varia RCT715", capabilities: Self.combo)]
        let store = makeStore(
            pairedSensors: [
                PairedSensor(peripheralID: Self.pairedID, role: .radar, displayName: "Varia RCT715")
            ],
            bleCSCClient: ble
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.pairButtonTapped(Self.pairedID))
        await store.send(.devicesUpdated(found))
        #expect(store.state.roleDialog != nil)
        await store.send(.roleDialog(.presented(.chose(peripheralID: Self.pairedID, roles: [.speed]))))
        await store.finish()

        #expect(store.state.preferences.pairedSensors == [
            PairedSensor(peripheralID: Self.pairedID, role: .radar, displayName: "Varia RCT715"),
            PairedSensor(peripheralID: Self.pairedID, role: .speed, displayName: "Varia RCT715")
        ])
        // Only the CSC role reaches the CSC client.
        #expect(pushed.value == [[Self.pairedID: [.speed]]])
    }

    /// Unpair on a CSC-only screen means "release speed and cadence". The radar pairing
    /// was made elsewhere and is not this button's to revoke.
    @Test("Unpairing releases only the CSC roles, not the radar record")
    func unpairKeepsNonCSCRecords() async {
        let log = LockIsolated<[ClientCall]>([])
        let store = makeStore(
            devices: [Self.sensor(id: Self.pairedID, name: "Varia RCT715", roles: [.speed], state: .active)],
            pairedSensors: [
                PairedSensor(peripheralID: Self.pairedID, role: .radar, displayName: "Varia RCT715"),
                PairedSensor(peripheralID: Self.pairedID, role: .speed, displayName: "Varia RCT715")
            ],
            bleCSCClient: Self.recordingClient(into: log)
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.unpairButtonTapped(Self.pairedID))
        await store.finish()

        #expect(store.state.preferences.pairedSensors == [
            PairedSensor(peripheralID: Self.pairedID, role: .radar, displayName: "Varia RCT715")
        ])
        // The CSC client is told the peripheral holds nothing *it* cares about, and the
        // radar record never reaches it.
        #expect(log.value == [.setPairedSensors([:]), .unpair(Self.pairedID)])
    }

    /// Membership in `pairedSensors` is not membership in *this screen's* pairings. A
    /// CSC-capable device already paired for heart rate holds no CSC role, so hiding it
    /// from both sections leaves the rider no way to give it speed or cadence.
    @Test("A device paired only for heart rate is still offered a CSC role")
    func nonCSCPairingDoesNotHideTheDevice() {
        let store = makeStore(
            devices: [Self.sensor(id: Self.pairedID, name: "Wahoo TICKR", capabilities: Self.combo)],
            pairedSensors: [
                PairedSensor(peripheralID: Self.pairedID, role: .heartRate, displayName: "Wahoo TICKR")
            ]
        )

        #expect(store.state.pairedDevices.isEmpty)
        #expect(store.state.availableDevices.map(\.id) == [Self.pairedID])
        // Not re-promptable either: there is no CSC pairing here to reassign.
        #expect(store.state.reassignableIDs.isEmpty)
    }

    /// A 0x2A5C read describes the CSC profile and nothing else, so a correction made
    /// on that evidence must not reach a radar record for the same peripheral.
    @Test("Capability reconciliation cannot delete a radar record")
    func reconciliationKeepsNonCSCRecords() async {
        let store = makeStore(
            pairedSensors: [
                PairedSensor(peripheralID: Self.pairedID, role: .radar, displayName: "Varia RCT715"),
                PairedSensor(peripheralID: Self.pairedID, role: .cadence, displayName: "Varia RCT715")
            ]
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        // Firmware now reports wheel data only — the cadence record has to go.
        await store.send(.devicesUpdated([
            Self.sensor(id: Self.pairedID, name: "Varia RCT715", roles: [.cadence],
                        state: .active, capabilities: Self.wheelOnly)
        ]))
        await store.finish()

        #expect(store.state.preferences.pairedSensors == [
            PairedSensor(peripheralID: Self.pairedID, role: .radar, displayName: "Varia RCT715")
        ])
    }
}
