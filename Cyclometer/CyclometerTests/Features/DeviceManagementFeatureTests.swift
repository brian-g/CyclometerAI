import Testing
import Foundation
import ComposableArchitecture
@testable import Cyclometer

@MainActor
@Suite("DeviceManagementFeature")
struct DeviceManagementFeatureTests {

    private static let pairedID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    private static let availableID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
    private static let radarID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C3")!
    private static let hrID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D4")!
    /// A second paired CSC sensor, for the collisions that displace two incumbents.
    private static let otherPairedID = UUID(uuidString: "00000000-0000-0000-0000-0000000000E5")!

    private static let combo = BLECSCClient.Capabilities(
        supportsWheelRevolutions: true, supportsCrankRevolutions: true
    )
    private static let wheelOnly = BLECSCClient.Capabilities(
        supportsWheelRevolutions: true, supportsCrankRevolutions: false
    )
    private static let crankOnly = BLECSCClient.Capabilities(
        supportsWheelRevolutions: false, supportsCrankRevolutions: true
    )

    /// A CSC row as `BLECSCClient` would emit it. Kind is fixed here because the CSC
    /// stream only ever carries `.speedCadence`; the radar and HR helpers below are the
    /// other two sources the merge draws on.
    private static func sensor(
        id: UUID,
        name: String?,
        roles: Set<SensorRole> = [],
        state: SensorConnectionState? = nil,
        battery: Int? = nil,
        capabilities: CSCCapabilities? = nil
    ) -> DiscoveredDevice {
        .init(
            id: id, name: name, kinds: [.speedCadence], roles: roles,
            connectionState: state, batteryPercent: battery, capabilities: capabilities
        )
    }

    private static func radar(
        id: UUID, name: String?, paired: Bool = false, state: SensorConnectionState? = nil
    ) -> DiscoveredDevice {
        .init(id: id, name: name, kinds: [.radar],
              roles: paired ? [.radar] : [], connectionState: state)
    }

    private static func strap(
        id: UUID, name: String?, paired: Bool = false, state: SensorConnectionState? = nil
    ) -> DiscoveredDevice {
        .init(id: id, name: name, kinds: [.heartRate],
              roles: paired ? [.heartRate] : [], connectionState: state)
    }

    /// The unpaired CSC row a Pair tap is sent against.
    ///
    /// Seeded rather than implied: the button exists only because discovery put the row
    /// on screen, and since #100 the reducer reads that row's `kinds` to decide whether
    /// the sensor needs interrogating at all — a radar has nothing to read. Capabilities
    /// are absent here, as they are before 0x2A5C answers; each test's next
    /// `.devicesUpdated` is what delivers them.
    private static func rowToPair(
        id: UUID = DeviceManagementFeatureTests.availableID, name: String
    ) -> [DiscoveredDevice] {
        [Self.sensor(id: id, name: name)]
    }

    /// One log across every write endpoint, on all three clients. The ordering *between*
    /// them is the thing under test — a separate `LockIsolated` per endpoint can only
    /// show that each was called, which is what let two ordering races through review.
    private enum ClientCall: Equatable {
        case setPairedSensors([UUID: Set<SensorRole>])
        case setRoles(UUID, Set<SensorRole>)
        case unpair(UUID)
        /// `VariaRadarClient.setPairedSensor`. A single-slot client moves the gate and
        /// the connection together, so this one call is the whole operation — there is
        /// no separate `unpair` for it to be ordered against (#100).
        case setRadarPaired(UUID?)
        /// `BLEHRClient.setPairedSensor`, same contract as `setRadarPaired`.
        case setHRPaired(UUID?)
    }

    private static func recordingClient(into log: LockIsolated<[ClientCall]>) -> BLECSCClient {
        var ble = BLECSCClient.testValue
        ble.setPairedSensors = { map in log.withValue { $0.append(.setPairedSensors(map)) } }
        ble.setRoles = { id, roles in log.withValue { $0.append(.setRoles(id, roles)) } }
        ble.unpair = { id in log.withValue { $0.append(.unpair(id)) } }
        return ble
    }

    private static func recordingRadarClient(
        into log: LockIsolated<[ClientCall]>
    ) -> VariaRadarClient {
        var radar = VariaRadarClient.testValue
        radar.setPairedSensor = { id in log.withValue { $0.append(.setRadarPaired(id)) } }
        return radar
    }

    private static func recordingHRClient(into log: LockIsolated<[ClientCall]>) -> BLEHRClient {
        var hr = BLEHRClient.testValue
        hr.setPairedSensor = { id in log.withValue { $0.append(.setHRPaired(id)) } }
        return hr
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

    /// The collision alert literal, rebuilt here for the same reason as
    /// `expectedDialog`. The title and message are passed in rather than derived, so
    /// each test states the exact copy it expects instead of re-deriving the reducer's
    /// branching and agreeing with whatever it produces.
    private static func expectedCollisionAlert(
        for id: UUID,
        roles: Set<SensorRole>,
        title: String,
        message: String? = nil
    ) -> AlertState<DeviceManagementFeature.Action.CollisionChoice> {
        AlertState(
            title: { TextState(title) },
            actions: {
                ButtonState(role: .destructive, action: .replace(peripheralID: id, roles: roles)) {
                    TextState("Replace")
                }
                ButtonState(role: .cancel) { TextState("Cancel") }
            },
            message: message.map { text in { TextState(text) } }
        )
    }

    /// Each store gets its own in-memory file system so persisted pairings cannot
    /// leak between tests. Seeding happens inside the same scope, otherwise the seed
    /// and the store would read different storage — same idiom as SettingsFeatureTests.
    private func makeStore(
        devices: [DiscoveredDevice] = [],
        radarDevices: [DiscoveredDevice] = [],
        hrDevices: [DiscoveredDevice] = [],
        pairedSensors: [PairedSensor] = [],
        bleCSCClient: BLECSCClient = .testValue,
        variaRadarClient: VariaRadarClient = .testValue,
        bleHRClient: BLEHRClient = .testValue,
        clock: any Clock<Duration> = TestClock()
    ) -> TestStoreOf<DeviceManagementFeature> {
        let storage = FileStorage.inMemory
        var sources: [SensorKind: [DiscoveredDevice]] = [:]
        if !devices.isEmpty { sources[.speedCadence] = devices }
        if !radarDevices.isEmpty { sources[.radar] = radarDevices }
        if !hrDevices.isEmpty { sources[.heartRate] = hrDevices }
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.pairedSensors = pairedSensors }
            return TestStore(
                initialState: DeviceManagementFeature.State(sources: sources)
            ) {
                DeviceManagementFeature()
            } withDependencies: {
                $0.bleCSCClient = bleCSCClient
                $0.variaRadarClient = variaRadarClient
                $0.bleHRClient = bleHRClient
                // A TestClock leaves the sweep timer suspended, so `.task` tests finish
                // on their own terms; the sweep test advances it deliberately.
                $0.continuousClock = clock
                $0.defaultFileStorage = storage
            }
        }
    }

    // MARK: Scanning

    /// One log across all three clients' scan endpoints. The point is the *balance*
    /// between them: three separate counters can each show "begun once, ended once"
    /// while the screen has in fact left one client scanning forever.
    private enum ScanCall: Equatable {
        case begin(SensorKind)
        case end(SensorKind)
    }

    /// The three clients, each recording into one shared log and serving one stream.
    private static func recordingClients(
        into log: LockIsolated<[ScanCall]>,
        csc: AsyncStream<[DiscoveredDevice]> = AsyncStream { $0.finish() },
        radar: AsyncStream<[DiscoveredDevice]> = AsyncStream { $0.finish() },
        hr: AsyncStream<[DiscoveredDevice]> = AsyncStream { $0.finish() }
    ) -> (BLECSCClient, VariaRadarClient, BLEHRClient) {
        var cscClient = BLECSCClient.testValue
        cscClient.beginPairingScan = { log.withValue { $0.append(.begin(.speedCadence)) } }
        cscClient.endPairingScan = { log.withValue { $0.append(.end(.speedCadence)) } }
        cscClient.discoveredDevices = { csc }

        var radarClient = VariaRadarClient.testValue
        radarClient.beginPairingScan = { log.withValue { $0.append(.begin(.radar)) } }
        radarClient.endPairingScan = { log.withValue { $0.append(.end(.radar)) } }
        radarClient.discoveredDevices = { radar }

        var hrClient = BLEHRClient.testValue
        hrClient.beginPairingScan = { log.withValue { $0.append(.begin(.heartRate)) } }
        hrClient.endPairingScan = { log.withValue { $0.append(.end(.heartRate)) } }
        hrClient.discoveredDevices = { hr }

        return (cscClient, radarClient, hrClient)
    }

    @Test("Appearing starts a pairing scan on every client and pipes each stream into state")
    func taskStartsScanAndSubscribes() async {
        let (stream, continuation) = AsyncStream<[DiscoveredDevice]>.makeStream()
        let log = LockIsolated<[ScanCall]>([])
        let (csc, radar, hr) = Self.recordingClients(into: log, csc: stream)

        let store = makeStore(bleCSCClient: csc, variaRadarClient: radar, bleHRClient: hr)
        await store.send(.task)
        #expect(log.value == [.begin(.speedCadence), .begin(.radar), .begin(.heartRate)])

        let found = [Self.sensor(id: Self.availableID, name: "GSC-10")]
        continuation.yield(found)
        await store.receive(\.devicesUpdated) {
            $0.sources[.speedCadence] = found
        }

        continuation.finish()
        // `.onDisappear` is what tears the screen's effects down — the sweep timer never
        // finishes on its own, so an exhaustive store would otherwise report it in flight.
        await store.send(.onDisappear)
        await store.finish()
    }

    @Test("Each client's stream lands in its own slice of state")
    func eachStreamFeedsItsOwnSource() async {
        let (radarStream, radarContinuation) = AsyncStream<[DiscoveredDevice]>.makeStream()
        let (hrStream, hrContinuation) = AsyncStream<[DiscoveredDevice]>.makeStream()
        let log = LockIsolated<[ScanCall]>([])
        let (csc, radar, hr) = Self.recordingClients(into: log, radar: radarStream, hr: hrStream)

        let store = makeStore(bleCSCClient: csc, variaRadarClient: radar, bleHRClient: hr)
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.task)

        let varia = [Self.radar(id: Self.radarID, name: "Varia RTL515")]
        radarContinuation.yield(varia)
        await store.receive(\.devicesUpdated) { $0.sources[.radar] = varia }

        let polar = [Self.strap(id: Self.hrID, name: "Polar H10")]
        hrContinuation.yield(polar)
        await store.receive(\.devicesUpdated) { $0.sources[.heartRate] = polar }

        #expect(store.state.devices.map(\.name) == ["Polar H10", "Varia RTL515"])

        radarContinuation.finish()
        hrContinuation.finish()
        await store.finish()
    }

    @Test("Leaving the screen ends the pairing scan on every client")
    func onDisappearEndsScan() async {
        let log = LockIsolated<[ScanCall]>([])
        let (csc, radar, hr) = Self.recordingClients(into: log)

        let store = makeStore(bleCSCClient: csc, variaRadarClient: radar, bleHRClient: hr)
        await store.send(.onDisappear)
        await store.finish()

        #expect(log.value == [.end(.speedCadence), .end(.radar), .end(.heartRate)])
    }

    @Test("Appear and disappear balance across all three clients")
    func scanLifecycleBalances() async {
        let log = LockIsolated<[ScanCall]>([])
        let (csc, radar, hr) = Self.recordingClients(into: log)

        let store = makeStore(bleCSCClient: csc, variaRadarClient: radar, bleHRClient: hr)
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.task)
        await store.send(.onDisappear)
        await store.finish()

        for kind in SensorKind.allCases {
            #expect(log.value.filter { $0 == .begin(kind) }.count == 1)
            #expect(log.value.filter { $0 == .end(kind) }.count == 1)
        }
    }

    /// The sweep is what drops a sensor that has been switched off: each
    /// `beginPairingScan` rotates the client's scan generation, and anything that fails
    /// to re-advertise across one is gone. Reusing `.refreshRequested` is deliberate —
    /// a second path would be free to drift from the one the rider's pull takes.
    @Test("The list re-checks what is still advertising on a timer while open")
    func sweepTimerRefreshesPeriodically() async {
        let log = LockIsolated<[ScanCall]>([])
        let (csc, radar, hr) = Self.recordingClients(into: log)
        let clock = TestClock()

        let store = makeStore(
            bleCSCClient: csc, variaRadarClient: radar, bleHRClient: hr, clock: clock
        )
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.task)
        log.withValue { $0.removeAll() }   // drop the three opening begins

        await clock.advance(by: DeviceManagementFeature.sweepInterval)
        await store.receive(\.refreshRequested)
        #expect(log.value == [
            .begin(.speedCadence), .end(.speedCadence),
            .begin(.radar), .end(.radar),
            .begin(.heartRate), .end(.heartRate)
        ])

        // ...and it keeps going, rather than firing once.
        log.withValue { $0.removeAll() }
        await clock.advance(by: DeviceManagementFeature.sweepInterval)
        await store.receive(\.refreshRequested)
        #expect(log.value.filter { $0 == .begin(.radar) }.count == 1)

        await store.send(.onDisappear)
        await store.finish()
    }

    /// Refresh takes the extra reference *before* releasing it, per client. The other
    /// order would let the refcount reach zero between the two calls and drop the radio
    /// mid-refresh — and on a client with no other holder, that is a real scan restart
    /// the rider would see as an empty list.
    @Test("Pull to refresh re-issues the scan on every client, staying balanced")
    func refreshRestartsEveryScan() async {
        let log = LockIsolated<[ScanCall]>([])
        let (csc, radar, hr) = Self.recordingClients(into: log)

        let store = makeStore(bleCSCClient: csc, variaRadarClient: radar, bleHRClient: hr)
        await store.send(.refreshRequested)
        await store.finish()

        #expect(log.value == [
            .begin(.speedCadence), .end(.speedCadence),
            .begin(.radar), .end(.radar),
            .begin(.heartRate), .end(.heartRate)
        ])
    }

    // MARK: Pairing and role selection

    @Test("Pair connects for interrogation and records the pairing as in flight")
    func pairStartsInterrogation() async {
        let paired = LockIsolated<[UUID]>([])
        var ble = BLECSCClient.testValue
        ble.pair = { id in paired.withValue { $0.append(id) } }

        let store = makeStore(devices: Self.rowToPair(name: "Wahoo RPM"), bleCSCClient: ble)
        await store.send(.pairButtonTapped(Self.availableID)) {
            $0.pendingPairing = Self.availableID
        }
        await store.finish()

        #expect(paired.value == [Self.availableID])
    }

    @Test("A combo sensor's capabilities raise the role prompt")
    func comboCapabilitiesPromptForRole() async {
        let store = makeStore(devices: Self.rowToPair(name: "Wahoo RPM"))
        await store.send(.pairButtonTapped(Self.availableID)) {
            $0.pendingPairing = Self.availableID
        }

        let found = [Self.sensor(id: Self.availableID, name: "Wahoo RPM", capabilities: Self.combo)]
        await store.send(.devicesUpdated(.speedCadence, found)) {
            $0.sources[.speedCadence] = found
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

        let store = makeStore(devices: Self.rowToPair(name: "GSC-10"), bleCSCClient: ble)
        await store.send(.pairButtonTapped(Self.availableID)) {
            $0.pendingPairing = Self.availableID
        }

        let found = [Self.sensor(id: Self.availableID, name: "GSC-10", capabilities: capabilities)]
        await store.send(.devicesUpdated(.speedCadence, found)) {
            $0.sources[.speedCadence] = found
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
        let store = makeStore(devices: Self.rowToPair(name: "Wahoo RPM"), bleCSCClient: ble)
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.pairButtonTapped(Self.availableID))
        // The capabilities arriving is what raises the prompt; sending the choice
        // without it would be a presentation action with no presented state.
        await store.send(.devicesUpdated(.speedCadence, found))
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
        let store = makeStore(devices: Self.rowToPair(name: "Wahoo RPM"), bleCSCClient: ble)
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.pairButtonTapped(Self.availableID))
        await store.send(.devicesUpdated(.speedCadence, found))
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
            devices: Self.rowToPair(name: "GSC-10"),
            pairedSensors: [PairedSensor(peripheralID: Self.pairedID, role: .speed, displayName: "Wahoo RPM")]
        )
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.pairButtonTapped(Self.availableID))
        await store.send(.devicesUpdated(.speedCadence, found))
        await store.send(.roleDialog(.presented(.chose(peripheralID: Self.availableID, roles: [.speed]))))
        // Speed was occupied, so the move is now the rider's to confirm (#99).
        await store.send(.collisionAlert(.presented(.replace(peripheralID: Self.availableID, roles: [.speed]))))
        await store.finish()

        // The incumbent's speed record is gone — one sensor per role, app-wide.
        #expect(store.state.preferences.pairedSensors == [
            PairedSensor(peripheralID: Self.availableID, role: .speed, displayName: "GSC-10")
        ])
    }

    // MARK: Role collision — replace or cancel (#99)

    /// Speed occupied by `pairedID`, and `availableID` interrogated and claiming it.
    /// The shape every collision test below starts from.
    private static func speedCollisionDevices() -> [DiscoveredDevice] {
        [
            Self.sensor(id: Self.pairedID, name: "Wahoo SPEED", roles: [.speed],
                        state: .active, capabilities: Self.wheelOnly),
            Self.sensor(id: Self.availableID, name: "GSC-10", capabilities: Self.combo)
        ]
    }

    private static let speedIncumbent = PairedSensor(
        peripheralID: pairedID, role: .speed, displayName: "Wahoo SPEED"
    )

    @Test("Claiming an occupied role raises the confirmation instead of writing")
    func collisionRaisesConfirmation() async {
        let log = LockIsolated<[ClientCall]>([])
        let store = makeStore(
            devices: Self.rowToPair(name: "GSC-10"),
            pairedSensors: [Self.speedIncumbent],
            bleCSCClient: Self.recordingClient(into: log)
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.pairButtonTapped(Self.availableID))
        await store.send(.devicesUpdated(.speedCadence, Self.speedCollisionDevices()))
        await store.send(.roleDialog(.presented(.chose(peripheralID: Self.availableID, roles: [.speed])))) {
            $0.collisionAlert = Self.expectedCollisionAlert(
                for: Self.availableID, roles: [.speed],
                title: "Speed is already assigned to Wahoo SPEED."
            )
        }
        await store.finish()

        // Nothing is written until the rider answers, and the interrogated peripheral
        // stays in flight — that is what lets Cancel release it.
        #expect(log.value == [])
        #expect(store.state.preferences.pairedSensors == [Self.speedIncumbent])
        #expect(store.state.pendingPairing == Self.availableID)
    }

    @Test("Replace pushes the assignments before moving the role")
    func replaceCommitsTheWrite() async {
        let log = LockIsolated<[ClientCall]>([])
        let store = makeStore(
            devices: Self.rowToPair(name: "GSC-10"),
            pairedSensors: [Self.speedIncumbent],
            bleCSCClient: Self.recordingClient(into: log)
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.pairButtonTapped(Self.availableID))
        await store.send(.devicesUpdated(.speedCadence, Self.speedCollisionDevices()))
        await store.send(.roleDialog(.presented(.chose(peripheralID: Self.availableID, roles: [.speed]))))
        await store.send(.collisionAlert(.presented(.replace(peripheralID: Self.availableID, roles: [.speed]))))
        await store.finish()

        // One `setRoles` moves the role for *both* peripherals: the client subtracts it
        // from the incumbent's slot inside the same lock, and disconnects a slot left
        // holding nothing. A second call naming the incumbent would be dead code.
        #expect(log.value == [
            .setPairedSensors([Self.availableID: [.speed]]),
            .setRoles(Self.availableID, [.speed])
        ])
        #expect(store.state.preferences.pairedSensors == [
            PairedSensor(peripheralID: Self.availableID, role: .speed, displayName: "GSC-10")
        ])
        #expect(store.state.pendingPairing == nil)
    }

    @Test("Cancel releases the interrogated peripheral and writes nothing")
    func cancelReleasesTheInterrogatedPeripheral() async {
        let log = LockIsolated<[ClientCall]>([])
        let store = makeStore(
            devices: Self.rowToPair(name: "GSC-10"),
            pairedSensors: [Self.speedIncumbent],
            bleCSCClient: Self.recordingClient(into: log)
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.pairButtonTapped(Self.availableID))
        await store.send(.devicesUpdated(.speedCadence, Self.speedCollisionDevices()))
        await store.send(.roleDialog(.presented(.chose(peripheralID: Self.availableID, roles: [.speed]))))
        await store.send(.collisionAlert(.dismiss))
        await store.finish()

        // It is connected holding no roles; leaving it there is an invisible
        // half-pairing. No `setPairedSensors` — nothing was ever written for it.
        #expect(log.value == [.unpair(Self.availableID)])
        #expect(store.state.preferences.pairedSensors == [Self.speedIncumbent])
        #expect(store.state.pendingPairing == nil)
    }

    @Test("Cancelling a reassignment releases nothing — it keeps what it had")
    func cancelOnReassignmentKeepsWhatItHad() async {
        let log = LockIsolated<[ClientCall]>([])
        let records = [
            PairedSensor(peripheralID: Self.pairedID, role: .cadence, displayName: "Wahoo RPM"),
            PairedSensor(peripheralID: Self.availableID, role: .speed, displayName: "Wahoo SPEED")
        ]
        let store = makeStore(
            devices: [
                Self.sensor(id: Self.pairedID, name: "Wahoo RPM", roles: [.cadence],
                            state: .active, capabilities: Self.combo),
                Self.sensor(id: Self.availableID, name: "Wahoo SPEED", roles: [.speed],
                            state: .active, capabilities: Self.wheelOnly)
            ],
            pairedSensors: records,
            bleCSCClient: Self.recordingClient(into: log)
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.rowTapped(Self.pairedID))
        await store.send(.roleDialog(.presented(.chose(peripheralID: Self.pairedID, roles: [.speed]))))
        await store.send(.collisionAlert(.dismiss))
        await store.finish()

        // No pairing was in flight — `pendingPairing` is what tells the two cases
        // apart, and unpairing here would drop a working sensor the rider never touched.
        #expect(log.value == [])
        #expect(store.state.preferences.pairedSensors == records)
    }

    @Test("Both against two occupied roles raises one confirmation naming both")
    func bothAgainstTwoIncumbentsRaisesOneConfirmation() async {
        let log = LockIsolated<[ClientCall]>([])
        let store = makeStore(
            devices: Self.rowToPair(name: "Wahoo RPM"),
            pairedSensors: [
                Self.speedIncumbent,
                PairedSensor(peripheralID: Self.otherPairedID, role: .cadence, displayName: "Garmin GSC-10")
            ],
            bleCSCClient: Self.recordingClient(into: log)
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.pairButtonTapped(Self.availableID))
        await store.send(.devicesUpdated(.speedCadence, [
            Self.sensor(id: Self.availableID, name: "Wahoo RPM", capabilities: Self.combo)
        ]))
        await store.send(.roleDialog(.presented(
            .chose(peripheralID: Self.availableID, roles: [.speed, .cadence])
        ))) {
            // One alert, not two. Roles are listed in `SensorRole.allCases` order so
            // the copy cannot reorder between runs.
            $0.collisionAlert = Self.expectedCollisionAlert(
                for: Self.availableID, roles: [.speed, .cadence],
                title: "Replace two sensors?",
                message: """
                    Speed is assigned to Wahoo SPEED.
                    Cadence is assigned to Garmin GSC-10.
                    """
            )
        }
        await store.finish()
        #expect(log.value == [])
    }

    @Test("Both against one combo holding both names that sensor, not \"two sensors\"")
    func bothAgainstOneComboNamesIt() async {
        let log = LockIsolated<[ClientCall]>([])
        let store = makeStore(
            devices: Self.rowToPair(name: "GSC-10"),
            pairedSensors: [
                PairedSensor(peripheralID: Self.pairedID, role: .speed, displayName: "Wahoo RPM"),
                PairedSensor(peripheralID: Self.pairedID, role: .cadence, displayName: "Wahoo RPM")
            ],
            bleCSCClient: Self.recordingClient(into: log)
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.pairButtonTapped(Self.availableID))
        await store.send(.devicesUpdated(.speedCadence, [
            Self.sensor(id: Self.availableID, name: "GSC-10", capabilities: Self.combo)
        ]))
        await store.send(.roleDialog(.presented(
            .chose(peripheralID: Self.availableID, roles: [.speed, .cadence])
        ))) {
            $0.collisionAlert = Self.expectedCollisionAlert(
                for: Self.availableID, roles: [.speed, .cadence],
                title: "Replace Wahoo RPM?",
                message: """
                    Speed is assigned to Wahoo RPM.
                    Cadence is assigned to Wahoo RPM.
                    """
            )
        }
        await store.finish()
        #expect(log.value == [])
    }

    @Test("A partial collision replaces only the colliding role")
    func partialCollisionKeepsTheOtherRole() async {
        let log = LockIsolated<[ClientCall]>([])
        let store = makeStore(
            devices: Self.rowToPair(name: "GSC-10"),
            pairedSensors: [
                PairedSensor(peripheralID: Self.pairedID, role: .speed, displayName: "Wahoo RPM"),
                PairedSensor(peripheralID: Self.pairedID, role: .cadence, displayName: "Wahoo RPM")
            ],
            bleCSCClient: Self.recordingClient(into: log)
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.pairButtonTapped(Self.availableID))
        await store.send(.devicesUpdated(.speedCadence, [
            Self.sensor(id: Self.pairedID, name: "Wahoo RPM", roles: [.speed, .cadence],
                        state: .active, capabilities: Self.combo),
            Self.sensor(id: Self.availableID, name: "GSC-10", capabilities: Self.wheelOnly)
        ]))
        await store.send(.collisionAlert(.presented(.replace(peripheralID: Self.availableID, roles: [.speed]))))
        await store.finish()

        // The incumbent keeps cadence and stays connected under it — the client
        // subtracts only the claimed role, and the slot survives because it is not empty.
        #expect(store.state.preferences.pairedSensors == [
            PairedSensor(peripheralID: Self.pairedID, role: .cadence, displayName: "Wahoo RPM"),
            PairedSensor(peripheralID: Self.availableID, role: .speed, displayName: "GSC-10")
        ])
        #expect(log.value == [
            .setPairedSensors([Self.pairedID: [.cadence], Self.availableID: [.speed]]),
            .setRoles(Self.availableID, [.speed])
        ])
    }

    @Test("A single-capability sensor skips the role prompt but not the collision check")
    func singleCapabilitySkipsPromptNotCollisionCheck() async {
        let log = LockIsolated<[ClientCall]>([])
        let found = [
            Self.sensor(id: Self.pairedID, name: "Wahoo SPEED", roles: [.speed],
                        state: .active, capabilities: Self.wheelOnly),
            Self.sensor(id: Self.availableID, name: "GSC-10", capabilities: Self.wheelOnly)
        ]
        let store = makeStore(
            devices: Self.rowToPair(name: "GSC-10"),
            pairedSensors: [Self.speedIncumbent],
            bleCSCClient: Self.recordingClient(into: log)
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.pairButtonTapped(Self.availableID))
        await store.send(.devicesUpdated(.speedCadence, found)) {
            $0.collisionAlert = Self.expectedCollisionAlert(
                for: Self.availableID, roles: [.speed],
                title: "Speed is already assigned to Wahoo SPEED."
            )
        }
        await store.finish()

        // Nothing to ask about the role, everything to ask about the incumbent.
        #expect(store.state.roleDialog == nil)
        #expect(log.value == [])
    }

    @Test("An incumbent that is out of range is still named")
    func outOfRangeIncumbentIsNamed() async {
        // Only the new sensor is advertising; the incumbent appears on no stream, so
        // its name can come from nowhere but its own record.
        let log = LockIsolated<[ClientCall]>([])
        let store = makeStore(
            devices: Self.rowToPair(name: "GSC-10"),
            pairedSensors: [Self.speedIncumbent],
            bleCSCClient: Self.recordingClient(into: log)
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.pairButtonTapped(Self.availableID))
        await store.send(.devicesUpdated(.speedCadence, [
            Self.sensor(id: Self.availableID, name: "GSC-10", capabilities: Self.wheelOnly)
        ])) {
            $0.collisionAlert = Self.expectedCollisionAlert(
                for: Self.availableID, roles: [.speed],
                title: "Speed is already assigned to Wahoo SPEED."
            )
        }
        await store.finish()

        // The displaced incumbent is not here to be re-paired, so writing before the
        // rider answers would be the most damaging version of this bug.
        #expect(log.value == [])
        #expect(store.state.preferences.pairedSensors == [Self.speedIncumbent])
    }

    @Test("A reassignment prompt is refused while a pairing is in flight")
    func reassignmentIsRefusedDuringAnInterrogation() async {
        let log = LockIsolated<[ClientCall]>([])
        let records = [
            PairedSensor(peripheralID: Self.pairedID, role: .cadence, displayName: "Wahoo RPM"),
            PairedSensor(peripheralID: Self.otherPairedID, role: .speed, displayName: "Wahoo SPEED")
        ]
        let store = makeStore(
            devices: [
                Self.sensor(id: Self.pairedID, name: "Wahoo RPM", roles: [.cadence],
                            state: .active, capabilities: Self.combo),
                Self.sensor(id: Self.availableID, name: "GSC-10", capabilities: Self.combo)
            ],
            pairedSensors: records,
            bleCSCClient: Self.recordingClient(into: log)
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        // Pair tap on GSC-10 starts a 0x2A5C read; the list stays interactive, so the
        // rider can reach a paired combo row before it answers.
        await store.send(.pairButtonTapped(Self.availableID))
        await store.send(.rowTapped(Self.pairedID))
        await store.finish()

        // Raising it would put `pendingPairing` and the prompt on screen out of step:
        // Cancel would then unpair GSC-10, which the rider never cancelled.
        #expect(store.state.roleDialog == nil)
        #expect(store.state.pendingPairing == Self.availableID)
        #expect(log.value == [])
        #expect(store.state.preferences.pairedSensors == records)
    }

    @Test("A device update while the confirmation is up does not clobber it")
    func deviceUpdateDoesNotClobberTheConfirmation() async {
        let log = LockIsolated<[ClientCall]>([])
        let found = Self.speedCollisionDevices()
        let store = makeStore(
            devices: Self.rowToPair(name: "GSC-10"),
            pairedSensors: [Self.speedIncumbent],
            bleCSCClient: Self.recordingClient(into: log)
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.pairButtonTapped(Self.availableID))
        await store.send(.devicesUpdated(.speedCadence, found))
        await store.send(.roleDialog(.presented(.chose(peripheralID: Self.availableID, roles: [.speed]))))
        let raised = store.state.collisionAlert
        #expect(raised != nil)

        // The sweep timer re-broadcasts every 10s and `pendingPairing` is still set,
        // so without the prompt guard this re-raises the role sheet over the alert.
        await store.send(.devicesUpdated(.speedCadence, found))
        await store.finish()

        #expect(store.state.roleDialog == nil)
        #expect(store.state.collisionAlert == raised)
        #expect(log.value == [])
    }

    @Test("A free role is written without a confirmation")
    func noCollisionWritesWithoutPrompting() async {
        let log = LockIsolated<[ClientCall]>([])
        let store = makeStore(
            devices: Self.rowToPair(name: "GSC-10"),
            pairedSensors: [Self.speedIncumbent],
            bleCSCClient: Self.recordingClient(into: log)
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.pairButtonTapped(Self.availableID))
        // Cadence is unheld, so claiming it displaces nobody.
        await store.send(.devicesUpdated(.speedCadence, [
            Self.sensor(id: Self.availableID, name: "GSC-10", capabilities: Self.crankOnly)
        ]))
        await store.finish()

        #expect(store.state.collisionAlert == nil)
        #expect(log.value == [
            .setPairedSensors([Self.pairedID: [.speed], Self.availableID: [.cadence]]),
            .setRoles(Self.availableID, [.cadence])
        ])
    }

    // MARK: Radar and heart rate pairing (#100)

    /// Nothing to interrogate: the service the peripheral advertised is the role it
    /// fills, so the tap goes straight to the collision gate and writes. No
    /// `pendingPairing` either — the single-slot client connects on its own once it is
    /// told the ID, so there is no half-pairing for a cancel to have to release.
    @Test("Pairing a radar writes the record and points the client at it")
    func pairingARadarWritesTheRecord() async {
        let log = LockIsolated<[ClientCall]>([])
        let store = makeStore(
            radarDevices: [Self.radar(id: Self.radarID, name: "Varia RTL515")],
            bleCSCClient: Self.recordingClient(into: log),
            variaRadarClient: Self.recordingRadarClient(into: log)
        )

        await store.send(.pairButtonTapped(Self.radarID)) {
            $0.$preferences.withLock {
                $0.pairedSensors = [
                    PairedSensor(peripheralID: Self.radarID, role: .radar, displayName: "Varia RTL515")
                ]
            }
        }
        await store.finish()

        #expect(store.state.roleDialog == nil)
        #expect(store.state.pendingPairing == nil)
        // Nothing reaches the CSC client: a claim touching no CSC role cannot change its
        // map, and a radar must never reach a client looking for 0x1816 in any case.
        #expect(log.value == [.setRadarPaired(Self.radarID)])
    }

    @Test("Pairing a heart rate strap writes the record and points the client at it")
    func pairingAStrapWritesTheRecord() async {
        let log = LockIsolated<[ClientCall]>([])
        let store = makeStore(
            hrDevices: [Self.strap(id: Self.hrID, name: "Wahoo TICKR")],
            bleCSCClient: Self.recordingClient(into: log),
            bleHRClient: Self.recordingHRClient(into: log)
        )

        await store.send(.pairButtonTapped(Self.hrID)) {
            $0.$preferences.withLock {
                $0.pairedSensors = [
                    PairedSensor(peripheralID: Self.hrID, role: .heartRate, displayName: "Wahoo TICKR")
                ]
            }
        }
        await store.finish()

        #expect(log.value == [.setHRPaired(Self.hrID)])
    }

    /// One sensor per role holds for radar too, so a second one is the rider's call —
    /// and the incumbent needs no release of its own: pointing the single slot at the
    /// replacement tears the old connection down inside the same call.
    @Test("A second radar raises the collision, and Replace moves the slot")
    func secondRadarRaisesTheCollision() async {
        let log = LockIsolated<[ClientCall]>([])
        let incumbent = PairedSensor(
            peripheralID: Self.pairedID, role: .radar, displayName: "Varia RTL515"
        )
        let store = makeStore(
            radarDevices: [Self.radar(id: Self.radarID, name: "Varia RCT715")],
            pairedSensors: [incumbent],
            bleCSCClient: Self.recordingClient(into: log),
            variaRadarClient: Self.recordingRadarClient(into: log)
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.pairButtonTapped(Self.radarID)) {
            $0.collisionAlert = Self.expectedCollisionAlert(
                for: Self.radarID, roles: [.radar],
                title: "Radar is already assigned to Varia RTL515."
            )
        }
        #expect(log.value == [])
        #expect(store.state.preferences.pairedSensors == [incumbent])

        await store.send(.collisionAlert(.presented(.replace(peripheralID: Self.radarID, roles: [.radar]))))
        await store.finish()

        #expect(store.state.preferences.pairedSensors == [
            PairedSensor(peripheralID: Self.radarID, role: .radar, displayName: "Varia RCT715")
        ])
        #expect(log.value == [.setRadarPaired(Self.radarID)])
    }

    /// Cancelling a radar collision must not release anything: unlike a CSC pairing,
    /// nothing was connected to interrogate, so there is no peripheral in flight.
    @Test("Cancelling a radar collision leaves the incumbent in place")
    func cancellingARadarCollisionChangesNothing() async {
        let log = LockIsolated<[ClientCall]>([])
        let incumbent = PairedSensor(
            peripheralID: Self.pairedID, role: .radar, displayName: "Varia RTL515"
        )
        let store = makeStore(
            radarDevices: [Self.radar(id: Self.radarID, name: "Varia RCT715")],
            pairedSensors: [incumbent],
            bleCSCClient: Self.recordingClient(into: log),
            variaRadarClient: Self.recordingRadarClient(into: log)
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.pairButtonTapped(Self.radarID))
        await store.send(.collisionAlert(.dismiss))
        await store.finish()

        #expect(store.state.preferences.pairedSensors == [incumbent])
        #expect(store.state.pendingPairing == nil)
        #expect(log.value == [])
    }

    /// A radar and a strap are different roles, so pairing both displaces nothing.
    @Test("Radar and heart rate pairings coexist")
    func radarAndStrapCoexist() async {
        let log = LockIsolated<[ClientCall]>([])
        let store = makeStore(
            radarDevices: [Self.radar(id: Self.radarID, name: "Varia RTL515")],
            hrDevices: [Self.strap(id: Self.hrID, name: "Wahoo TICKR")],
            bleCSCClient: Self.recordingClient(into: log),
            variaRadarClient: Self.recordingRadarClient(into: log),
            bleHRClient: Self.recordingHRClient(into: log)
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.pairButtonTapped(Self.radarID))
        await store.send(.pairButtonTapped(Self.hrID))
        await store.finish()

        #expect(store.state.preferences.pairedSensors == [
            PairedSensor(peripheralID: Self.radarID, role: .radar, displayName: "Varia RTL515"),
            PairedSensor(peripheralID: Self.hrID, role: .heartRate, displayName: "Wahoo TICKR")
        ])
        #expect(store.state.collisionAlert == nil)
        #expect(log.value == [.setRadarPaired(Self.radarID), .setHRPaired(Self.hrID)])
    }

    /// Unpairing a radar is one call. `setPairedSensor(nil)` moves the gate and the
    /// connection together, so there is nothing to order against it.
    @Test("Unpairing a radar releases the slot")
    func unpairingARadarReleasesTheSlot() async {
        let log = LockIsolated<[ClientCall]>([])
        let store = makeStore(
            radarDevices: [Self.radar(id: Self.radarID, name: "Varia RTL515", paired: true, state: .active)],
            pairedSensors: [
                PairedSensor(peripheralID: Self.radarID, role: .radar, displayName: "Varia RTL515")
            ],
            bleCSCClient: Self.recordingClient(into: log),
            variaRadarClient: Self.recordingRadarClient(into: log)
        )

        await store.send(.unpairButtonTapped(Self.radarID)) {
            $0.$preferences.withLock { $0.pairedSensors = [] }
        }
        await store.finish()

        // No `setPairedSensors` and no `unpair`: the CSC client held nothing here, and
        // pushing an unchanged map at it would be noise on every radar unpair.
        #expect(log.value == [.setRadarPaired(nil)])
    }

    /// A Pair tap on a row that discovery has since swept does nothing. The reducer has
    /// no evidence of what the peripheral is, and guessing would mean opening a
    /// connection on the chance it speaks 0x1816.
    @Test("Pairing an unknown peripheral is a no-op")
    func pairingAnUnknownPeripheralDoesNothing() async {
        let log = LockIsolated<[ClientCall]>([])
        var csc = Self.recordingClient(into: log)
        csc.pair = { id in log.withValue { $0.append(.unpair(id)) } }
        let store = makeStore(
            bleCSCClient: csc,
            variaRadarClient: Self.recordingRadarClient(into: log),
            bleHRClient: Self.recordingHRClient(into: log)
        )

        await store.send(.pairButtonTapped(Self.availableID))
        await store.finish()

        #expect(store.state.preferences.pairedSensors.isEmpty)
        #expect(store.state.pendingPairing == nil)
        #expect(log.value == [])
    }

    // MARK: Sections and unpairing

    /// The flat list S11 renders: paired first, then discovered-but-unpaired, each half
    /// by name. Not one section per role — role is established at pairing time and shown
    /// in the subtitle (UX.md §S11).
    @Test("The flat list puts paired sensors first, then the rest, each half by name")
    func listedDevicesSortsPairedFirst() {
        let store = makeStore(
            devices: [
                Self.sensor(id: Self.availableID, name: "Wahoo SPEED"),
                Self.sensor(id: Self.pairedID, name: "Wahoo RPM", roles: [.cadence], state: .active)
            ],
            radarDevices: [Self.radar(id: Self.radarID, name: "Varia RTL515", paired: true, state: .active)],
            hrDevices: [Self.strap(id: Self.hrID, name: "Garmin HRM")],
            pairedSensors: [
                PairedSensor(peripheralID: Self.pairedID, role: .cadence, displayName: "Wahoo RPM"),
                PairedSensor(peripheralID: Self.radarID, role: .radar, displayName: "Varia RTL515")
            ]
        )

        #expect(store.state.listedDevices.map(\.name) == [
            "Varia RTL515", "Wahoo RPM",   // paired
            "Garmin HRM", "Wahoo SPEED"    // discovered
        ])
        #expect(store.state.pairedRoles == [
            Self.pairedID: [.cadence],
            Self.radarID: [.radar]
        ])
    }

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

    // MARK: Unified discovery (#98)

    @Test("Mixed advertisements produce one list, paired records first")
    func mixedFixturesProduceOneList() {
        let store = makeStore(
            devices: [Self.sensor(id: Self.availableID, name: "GSC-10")],
            radarDevices: [Self.radar(id: Self.radarID, name: "Varia RTL515")],
            hrDevices: [Self.strap(id: Self.hrID, name: "Polar H10", paired: true, state: .active)],
            pairedSensors: [
                PairedSensor(peripheralID: Self.hrID, role: .heartRate, displayName: "Polar H10")
            ]
        )

        #expect(store.state.pairedDevices.map(\.id) == [Self.hrID])
        #expect(store.state.availableDevices.map(\.name) == ["GSC-10", "Varia RTL515"])
    }

    /// The dedupe AC. A device advertising two supported services arrives on two
    /// streams; appending both would give the rider two rows for one piece of hardware,
    /// each claiming half of what it can do.
    @Test("A device advertising two supported services is one row carrying both tags")
    func multiProfileDeviceIsOneRow() {
        let combo = UUID(uuidString: "00000000-0000-0000-0000-0000000000E5")!
        let store = makeStore(
            devices: [Self.sensor(id: combo, name: "Combo", capabilities: Self.wheelOnly)],
            hrDevices: [Self.strap(id: combo, name: "Combo", paired: true, state: .active)]
        )

        #expect(store.state.devices.count == 1)
        let row = store.state.devices[0]
        #expect(row.kinds == [.speedCadence, .heartRate])
        #expect(row.roles == [.heartRate])
        // The CSC stream had no connection to report; HR's `.active` is the liveliest
        // answer and the one the row shows.
        #expect(row.connectionState == .active)
        // Capabilities survive the fold even though only one source could answer.
        #expect(row.capabilities == Self.wheelOnly)
    }

    /// A merge that dropped the disconnected half would be equally wrong — the point is
    /// that the row reflects whichever client is actually talking to the hardware.
    @Test("The liveliest connection state wins a merge")
    func mergePicksTheLiveliestState() {
        let combo = UUID(uuidString: "00000000-0000-0000-0000-0000000000E5")!
        let store = makeStore(
            devices: [Self.sensor(id: combo, name: "Combo", roles: [.speed], state: .reconnecting)],
            radarDevices: [Self.radar(id: combo, name: "Combo", paired: true, state: .disconnected)]
        )

        let row = store.state.devices[0]
        #expect(row.connectionState == .reconnecting)
        #expect(row.roles == [.speed, .radar])
    }

    /// UX.md §S11: a paired sensor that is out of range stays in the list showing
    /// Disconnected, so it can still be unpaired. Its row exists on no discovery stream
    /// and is synthesised from the record alone.
    @Test("A paired radar that is out of range is listed and marked disconnected")
    func outOfRangePairedRadarStillListed() {
        let store = makeStore(
            pairedSensors: [
                PairedSensor(peripheralID: Self.radarID, role: .radar, displayName: "Varia RTL515")
            ]
        )

        let row = try! #require(store.state.pairedDevices.first)
        #expect(store.state.pairedDevices.count == 1)
        #expect(row.id == Self.radarID)
        #expect(row.name == "Varia RTL515")
        #expect(row.kinds == [.radar])
        #expect(row.connectionState == .disconnected)
        #expect(store.state.availableDevices.isEmpty)
    }

    /// The case `DiscoveredDevice.isPaired` cannot express: the sensor is paired but
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
            devices: Self.rowToPair(name: "Wahoo RPM"),
            pairedSensors: [PairedSensor(peripheralID: Self.pairedID, role: .speed, displayName: "GSC-10")],
            bleCSCClient: Self.recordingClient(into: log)
        )
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.pairButtonTapped(Self.availableID))
        await store.send(.devicesUpdated(.speedCadence, found))
        await store.send(.roleDialog(.presented(.chose(peripheralID: Self.availableID, roles: [.speed]))))
        await store.send(.collisionAlert(.presented(.replace(peripheralID: Self.availableID, roles: [.speed]))))
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
        await store.send(.devicesUpdated(.speedCadence, found)) {
            $0.sources[.speedCadence] = found
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
        await store.send(.devicesUpdated(.speedCadence, found)) {
            $0.sources[.speedCadence] = found
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
        await store.send(.devicesUpdated(.speedCadence, found)) { $0.sources[.speedCadence] = found }
        await store.finish()

        #expect(log.value.isEmpty)
        #expect(store.state.preferences.pairedSensors == records)
    }

    @Test("Reconciliation does not disturb a pairing in flight")
    func reconciliationLeavesPendingPairingAlone() async {
        let log = LockIsolated<[ClientCall]>([])
        let store = makeStore(
            devices: Self.rowToPair(name: "GSC-10"),
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
        await store.send(.devicesUpdated(.speedCadence, found))
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

    // `PairedSensor` is one collection across every role (#93), and one peripheral can
    // hold records in more than one of them — a device advertising two supported
    // services is one row carrying both tags (#98). So a decision made about one profile
    // must be scoped to that profile: every case below fails against a predicate keyed
    // on `peripheralID` alone.

    /// A combo row's single Pair button has to claim everything the hardware can do, in
    /// one write — but only the CSC half of it is the CSC client's business.
    @Test("Pairing a two-profile peripheral claims both, and only CSC reaches that client")
    func pairingAComboClaimsEveryProfile() async {
        let log = LockIsolated<[ClientCall]>([])
        let combo = DiscoveredDevice(
            id: Self.pairedID, name: "Varia RCT715", kinds: [.speedCadence, .radar]
        )
        let store = makeStore(
            devices: [combo],
            bleCSCClient: Self.recordingClient(into: log),
            variaRadarClient: Self.recordingRadarClient(into: log)
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.pairButtonTapped(Self.pairedID))
        await store.send(.devicesUpdated(.speedCadence, [
            DiscoveredDevice(id: Self.pairedID, name: "Varia RCT715",
                             kinds: [.speedCadence, .radar], capabilities: Self.combo)
        ]))
        // The prompt only ever offers the CSC roles; radar rides along on the answer.
        #expect(store.state.roleDialog != nil)
        await store.send(.roleDialog(.presented(.chose(peripheralID: Self.pairedID, roles: [.speed]))))
        await store.finish()

        #expect(store.state.preferences.pairedSensors == [
            PairedSensor(peripheralID: Self.pairedID, role: .radar, displayName: "Varia RCT715"),
            PairedSensor(peripheralID: Self.pairedID, role: .speed, displayName: "Varia RCT715")
        ])
        #expect(log.value == [
            .setPairedSensors([Self.pairedID: [.speed]]),
            .setRoles(Self.pairedID, [.speed]),
            .setRadarPaired(Self.pairedID)
        ])
    }

    /// The radar record shares a UUID with the CSC sensor, so a `peripheralID`-keyed
    /// removal would delete a pairing the reassignment never touched.
    @Test("Reassigning a CSC role leaves the same peripheral's radar record alone")
    func reassignmentKeepsNonCSCRecordsForTheSamePeripheral() async {
        let log = LockIsolated<[ClientCall]>([])
        let combo = DiscoveredDevice(
            id: Self.pairedID, name: "Varia RCT715", kinds: [.speedCadence, .radar],
            roles: [.speed, .radar], connectionState: .active, capabilities: Self.combo
        )
        let store = makeStore(
            devices: [combo],
            pairedSensors: [
                PairedSensor(peripheralID: Self.pairedID, role: .radar, displayName: "Varia RCT715"),
                PairedSensor(peripheralID: Self.pairedID, role: .speed, displayName: "Varia RCT715")
            ],
            bleCSCClient: Self.recordingClient(into: log),
            variaRadarClient: Self.recordingRadarClient(into: log)
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.rowTapped(Self.pairedID))
        #expect(store.state.roleDialog != nil)
        await store.send(.roleDialog(.presented(.chose(peripheralID: Self.pairedID, roles: [.cadence]))))
        await store.finish()

        // Speed released, cadence taken, radar untouched.
        #expect(store.state.preferences.pairedSensors == [
            PairedSensor(peripheralID: Self.pairedID, role: .radar, displayName: "Varia RCT715"),
            PairedSensor(peripheralID: Self.pairedID, role: .cadence, displayName: "Varia RCT715")
        ])
    }

    /// One row, one button (UX.md §S11). The M6 reading — "CSC records only, the radar
    /// pairing was made elsewhere" — described a screen on which radar could not be
    /// paired at all; there is no longer an elsewhere.
    @Test("Unpairing releases every role the peripheral holds, on every client")
    func unpairReleasesEveryRole() async {
        let log = LockIsolated<[ClientCall]>([])
        let store = makeStore(
            devices: [Self.sensor(id: Self.pairedID, name: "Varia RCT715", roles: [.speed], state: .active)],
            pairedSensors: [
                PairedSensor(peripheralID: Self.pairedID, role: .radar, displayName: "Varia RCT715"),
                PairedSensor(peripheralID: Self.pairedID, role: .speed, displayName: "Varia RCT715")
            ],
            bleCSCClient: Self.recordingClient(into: log),
            variaRadarClient: Self.recordingRadarClient(into: log)
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.unpairButtonTapped(Self.pairedID))
        await store.finish()

        #expect(store.state.preferences.pairedSensors.isEmpty)
        // CSC closes its reconnect gate before the teardown; the radar client does both
        // in the one call, so nil is all it needs.
        #expect(log.value == [
            .setPairedSensors([:]),
            .unpair(Self.pairedID),
            .setRadarPaired(nil)
        ])
    }

    /// A peripheral paired in one profile is one row, listed once, whatever else it can
    /// do. Claiming its other profile is unpair-then-pair, because a Pair tap on a combo
    /// claims everything the hardware advertises in a single write (#100) — there is no
    /// longer a reason to claim profiles one at a time.
    @Test("A device paired only for heart rate is still one paired row")
    func nonCSCPairingDoesNotHideTheDevice() {
        let store = makeStore(
            devices: [Self.sensor(id: Self.pairedID, name: "Wahoo TICKR", capabilities: Self.combo)],
            pairedSensors: [
                PairedSensor(peripheralID: Self.pairedID, role: .heartRate, displayName: "Wahoo TICKR")
            ]
        )

        // It sorts to the top of the flat list — it *is* paired — and holds no CSC
        // record, which is what #93 protects: a CSC decision must not be able to reach
        // the heart rate record behind the same UUID.
        #expect(store.state.pairedDevices.map(\.id) == [Self.pairedID])
        #expect(store.state.listedDevices.map(\.id) == [Self.pairedID])
        #expect(store.state.availableDevices.isEmpty)
        #expect(store.state.pairedDevices[0].roles.isDisjoint(with: SensorRole.cscRoles))
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
        await store.send(.devicesUpdated(.speedCadence, [
            Self.sensor(id: Self.pairedID, name: "Varia RCT715", roles: [.cadence],
                        state: .active, capabilities: Self.wheelOnly)
        ]))
        await store.finish()

        #expect(store.state.preferences.pairedSensors == [
            PairedSensor(peripheralID: Self.pairedID, role: .radar, displayName: "Varia RCT715")
        ])
    }
}
