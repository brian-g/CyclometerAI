import Testing
import ComposableArchitecture
import CoreBluetooth
@testable import Cyclometer

private let radarServiceUUID = CBUUID(string: "6A4E3200-667B-11E3-949A-0800200C9A66")
private let radarAlertUUID   = CBUUID(string: "6A4E3202-667B-11E3-949A-0800200C9A66")
private let batteryServiceUUID = CBUUID(string: "180F")
private let batteryLevelUUID   = CBUUID(string: "2A19")

// MARK: - Payload parsing

@Suite("VariaRadarClient — alert payload parsing")
struct VariaRadarParseTests {

    @Test("Zero vehicles, clear level parses to empty array")
    func zeroVehiclesClear() {
        let targets = VariaRadarClient.parseAlert(from: Data([0x00, 0x00]))
        #expect(targets == [])
    }

    @Test("Single vehicle at danger level")
    func singleVehicleDanger() throws {
        let targets = try #require(VariaRadarClient.parseAlert(from: Data([0x03, 0x01, 25, 8])))
        #expect(targets.count == 1)
        #expect(targets[0].rangeMetres == 25)
        #expect(targets[0].relativeVelocityMPS == 8)
        #expect(targets[0].threatLevel == .danger)
        #expect(targets[0].id == VariaRadarClient.vehicleSlotIDs[0])
    }

    @Test("Advisory level (1) maps to warning")
    func advisoryMapsToWarning() throws {
        let targets = try #require(VariaRadarClient.parseAlert(from: Data([0x01, 0x01, 50, 3])))
        #expect(targets[0].threatLevel == .warning)
    }

    @Test("Caution level (2) maps to warning")
    func cautionMapsToWarning() throws {
        let targets = try #require(VariaRadarClient.parseAlert(from: Data([0x02, 0x01, 50, 3])))
        #expect(targets[0].threatLevel == .warning)
    }

    @Test("Eight vehicles parse with stable slot IDs")
    func eightVehicles() throws {
        var bytes: [UInt8] = [0x02, 0x08]
        for i in 0..<8 {
            bytes.append(UInt8(10 + i * 10))  // range
            bytes.append(UInt8(2 + i))        // speed
        }
        let targets = try #require(VariaRadarClient.parseAlert(from: Data(bytes)))
        #expect(targets.count == 8)
        for i in 0..<8 {
            #expect(targets[i].id == VariaRadarClient.vehicleSlotIDs[i])
            #expect(targets[i].rangeMetres == Double(10 + i * 10))
            #expect(targets[i].relativeVelocityMPS == Double(2 + i))
        }
    }

    @Test("Truncated vehicle record returns nil")
    func truncatedRecord() {
        // Count says 2 vehicles but only one record present.
        #expect(VariaRadarClient.parseAlert(from: Data([0x02, 0x02, 30, 5])) == nil)
    }

    @Test("Vehicle count above 8 returns nil")
    func countTooHigh() {
        var bytes: [UInt8] = [0x02, 0x09]
        bytes.append(contentsOf: Array(repeating: 0, count: 18))
        #expect(VariaRadarClient.parseAlert(from: Data(bytes)) == nil)
    }

    @Test("Alert level above 3 returns nil")
    func levelTooHigh() {
        #expect(VariaRadarClient.parseAlert(from: Data([0x04, 0x00])) == nil)
    }

    @Test("Empty and single-byte payloads return nil")
    func tooShort() {
        #expect(VariaRadarClient.parseAlert(from: Data()) == nil)
        #expect(VariaRadarClient.parseAlert(from: Data([0x02])) == nil)
    }

    @Test("Trailing extra bytes are ignored")
    func trailingBytesIgnored() throws {
        let targets = try #require(VariaRadarClient.parseAlert(from: Data([0x02, 0x01, 50, 3, 99, 99])))
        #expect(targets.count == 1)
        #expect(targets[0].rangeMetres == 50)
    }
}

// MARK: - Reconnect backoff

@Suite("VariaRadarClient — reconnect backoff")
struct VariaRadarBackoffTests {

    @Test("Backoff ladder is 1, 2, 4, 8, 16 then capped at 30 seconds")
    func backoffLadder() {
        let expected: [Duration] = [
            .seconds(1), .seconds(2), .seconds(4), .seconds(8),
            .seconds(16), .seconds(30), .seconds(30), .seconds(30),
        ]
        for (attempt, delay) in expected.enumerated() {
            #expect(VariaRadarClient.reconnectDelay(attempt: attempt) == delay)
        }
    }
}

// MARK: - Integration (controllable BLEClient + TestClock)

/// Time-limited: every assertion here awaits a broadcast stream that never finishes, so
/// a client that fails to emit hangs the test rather than failing it — which stalls the
/// whole suite instead of pointing at the bug. Individual tests run in ~1s.
@Suite("VariaRadarClient — live state machine", .timeLimit(.minutes(1)))
struct VariaRadarIntegrationTests {

    /// One log across every transport endpoint the pairing gate touches. The ordering
    /// *between* connect and disconnect is what BLE.md §5.0 is about — a separate
    /// `LockIsolated` per endpoint can only show that each was called, which is what let
    /// two ordering races through review on #67.
    private enum BLECall: Equatable {
        case startScanning([CBUUID])
        case stopScanning([CBUUID])
        case connect(UUID)
        case disconnect(UUID, String)
    }

    /// Controllable transport: events are injected by the test; every operation
    /// is recorded. `connectCalls` is a stream so backoff tests can await each
    /// reconnect attempt deterministically.
    private struct Harness {
        let client: VariaRadarClient
        let events: AsyncStream<BLEEvent>.Continuation
        let connectCalls: AsyncStream<UUID>
        let connectCount: LockIsolated<Int>
        let scanned: LockIsolated<[[CBUUID]]>
        let notified: LockIsolated<[(Bool, CBUUID)]>
        let servicesDiscovered: LockIsolated<[[CBUUID]?]>
        let reads: LockIsolated<[CBUUID]>
        let calls: LockIsolated<[BLECall]>
        let clock: TestClock<Duration>

        init() {
            let (eventStream, eventContinuation) = AsyncStream<BLEEvent>.makeStream()
            let (connectStream, connectContinuation) = AsyncStream<UUID>.makeStream()
            let connectCount = LockIsolated(0)
            let scanned = LockIsolated<[[CBUUID]]>([])
            let notified = LockIsolated<[(Bool, CBUUID)]>([])
            let servicesDiscovered = LockIsolated<[[CBUUID]?]>([])
            let reads = LockIsolated<[CBUUID]>([])
            let calls = LockIsolated<[BLECall]>([])
            let clock = TestClock()

            let bleClient = BLEClient(
                startScanning: { uuids in
                    scanned.withValue { $0.append(uuids) }
                    calls.withValue { $0.append(.startScanning(uuids)) }
                },
                stopScanning: { uuids in calls.withValue { $0.append(.stopScanning(uuids)) } },
                connect: { id, _ in
                    connectCount.withValue { $0 += 1 }
                    calls.withValue { $0.append(.connect(id)) }
                    connectContinuation.yield(id)
                },
                disconnect: { id, owner in
                    calls.withValue { $0.append(.disconnect(id, owner)) }
                },
                discoverServices: { _, uuids in
                    servicesDiscovered.withValue { $0.append(uuids) }
                },
                discoverCharacteristics: { _, _, _ in },
                setNotifyValue: { enabled, _, _, charUUID in
                    notified.withValue { $0.append((enabled, charUUID)) }
                },
                readValue: { _, _, charUUID in
                    reads.withValue { $0.append(charUUID) }
                },
                events: { eventStream },
                authorization: { .allowedAlways },
                requestAuthorization: { .allowedAlways }
            )

            self.client = VariaRadarClient.live(bleClient: bleClient, clock: clock)
            self.events = eventContinuation
            self.connectCalls = connectStream
            self.connectCount = connectCount
            self.scanned = scanned
            self.notified = notified
            self.servicesDiscovered = servicesDiscovered
            self.reads = reads
            self.calls = calls
            self.clock = clock
        }

        /// Tell the client this radar is paired, the way `AppFeature` does at launch.
        func pair(_ id: UUID?) async {
            await client.setPairedSensor(id)
        }

        /// Wait until the device list satisfies `predicate`, and return it.
        ///
        /// Events are handled on the client's own task, so yielding one and reading the
        /// list on the next line is a race. Tests that assert on connection state get a
        /// sync point for free from the state stream; device-list assertions need this.
        func devices(
            matching predicate: @Sendable ([DiscoveredDevice]) -> Bool
        ) async -> [DiscoveredDevice] {
            for await list in client.discoveredDevices() where predicate(list) { return list }
            return []
        }
    }

    @Test("Discovery sequence drives state machine to active and enables notifications")
    func discoveryToActive() async {
        let harness = Harness()
        let peripheralID = UUID()

        var states = harness.client.connectionState().makeAsyncIterator()
        #expect(await states.next() == .disconnected)  // replayed current state

        await harness.pair(peripheralID)
        await harness.client.startScanning()
        #expect(await states.next() == .scanning)
        #expect(harness.scanned.value == [[radarServiceUUID]])

        harness.events.yield(.discovered(
            id: peripheralID, name: "Varia RTL515", rssi: -60, services: [radarServiceUUID]
        ))
        #expect(await states.next() == .connecting)

        harness.events.yield(.connected(id: peripheralID))
        #expect(await states.next() == .connected)

        harness.events.yield(.servicesDiscovered(peripheralID: peripheralID, serviceUUIDs: [radarServiceUUID]))
        harness.events.yield(.characteristicsDiscovered(
            peripheralID: peripheralID, serviceUUID: radarServiceUUID, characteristicUUIDs: [radarAlertUUID]
        ))
        #expect(await states.next() == .active)

        // Event loop is sequential: by the time .active was broadcast, all
        // earlier transport calls have completed.
        #expect(harness.connectCount.value == 1)
        #expect(harness.notified.value.count == 1)
        #expect(harness.notified.value[0].0 == true)
        #expect(harness.notified.value[0].1 == radarAlertUUID)
    }

    @Test("Connecting discovers the battery service alongside the radar service")
    func connectDiscoversBatteryService() async {
        let harness = Harness()
        let peripheralID = UUID()

        var states = harness.client.connectionState().makeAsyncIterator()
        _ = await states.next()  // .disconnected
        await harness.client.connect(peripheralID)
        _ = await states.next()  // .connecting

        harness.events.yield(.connected(id: peripheralID))
        #expect(await states.next() == .connected)

        // One call carrying both. A second call for 0x180F would re-emit the full
        // service list and re-fire the alert characteristic's discover → notify chain.
        #expect(harness.servicesDiscovered.value.count == 1)
        #expect(harness.servicesDiscovered.value[0]?.contains(radarServiceUUID) == true)
        #expect(harness.servicesDiscovered.value[0]?.contains(batteryServiceUUID) == true)
    }

    @Test("Battery level is read on connect and published, then cleared on disconnect")
    func batteryLevelReadAndCleared() async {
        let harness = Harness()
        let peripheralID = UUID()

        var states = harness.client.connectionState().makeAsyncIterator()
        _ = await states.next()  // .disconnected
        await harness.client.connect(peripheralID)
        _ = await states.next()  // .connecting

        var battery = harness.client.batteryLevel().makeAsyncIterator()
        #expect(await battery.next() == Int?.none)  // replayed: nothing read yet

        harness.events.yield(.connected(id: peripheralID))
        _ = await states.next()  // .connected — the handshake below follows it
        harness.events.yield(.servicesDiscovered(
            peripheralID: peripheralID, serviceUUIDs: [radarServiceUUID, batteryServiceUUID]
        ))
        harness.events.yield(.characteristicsDiscovered(
            peripheralID: peripheralID, serviceUUID: batteryServiceUUID,
            characteristicUUIDs: [batteryLevelUUID]
        ))
        // Stands in for the peripheral answering the read.
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: peripheralID, characteristicUUID: batteryLevelUUID, value: Data([0x52])
        ))

        #expect(await battery.next() == 82)
        #expect(harness.reads.value == [batteryLevelUUID])

        // A stale level next to a reconnecting radar would read as current.
        harness.events.yield(.disconnected(id: peripheralID, error: nil))
        #expect(await battery.next() == Int?.none)
    }

    /// Battery is read once per connection, so a subscriber that arrives afterwards —
    /// the Start sheet's `.task`, typically — only learns anything by replay.
    @Test("A late battery subscriber gets the current level replayed")
    func batteryReplaysForLateSubscriber() async {
        let harness = Harness()
        let peripheralID = UUID()

        var states = harness.client.connectionState().makeAsyncIterator()
        _ = await states.next()
        await harness.client.connect(peripheralID)
        _ = await states.next()

        var early = harness.client.batteryLevel().makeAsyncIterator()
        _ = await early.next()

        harness.events.yield(.characteristicValueUpdated(
            peripheralID: peripheralID, characteristicUUID: batteryLevelUUID, value: Data([0x2A])
        ))
        #expect(await early.next() == 42)   // sync point: the reading has landed

        var late = harness.client.batteryLevel().makeAsyncIterator()
        #expect(await late.next() == 42)
    }

    /// Same asymmetry as the HR client: `disconnect()` clears the target, so the
    /// `.disconnected` branch that would clear the level can no longer match.
    @Test("User disconnect clears the battery level for later subscribers")
    func userDisconnectClearsReplayedBattery() async {
        let harness = Harness()
        let peripheralID = UUID()

        var states = harness.client.connectionState().makeAsyncIterator()
        _ = await states.next()
        await harness.client.connect(peripheralID)
        _ = await states.next()

        var battery = harness.client.batteryLevel().makeAsyncIterator()
        _ = await battery.next()
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: peripheralID, characteristicUUID: batteryLevelUUID, value: Data([0x52])
        ))
        #expect(await battery.next() == 82)   // sync point

        await harness.client.disconnect()
        harness.events.yield(.disconnected(id: peripheralID, error: nil))

        var late = harness.client.batteryLevel().makeAsyncIterator()
        #expect(await late.next() == Int?.none)
    }

    @Test("Alert notification yields parsed targets; malformed payloads are dropped")
    func notificationYieldsTargets() async {
        let harness = Harness()
        let peripheralID = UUID()

        var states = harness.client.connectionState().makeAsyncIterator()
        _ = await states.next()
        await harness.client.connect(peripheralID)
        _ = await states.next()  // .connecting

        var targets = harness.client.radarTargets().makeAsyncIterator()

        // Malformed first (dropped — no emission), then a valid 2-vehicle payload.
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: peripheralID, characteristicUUID: radarAlertUUID, value: Data([0x04, 0x00])
        ))
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: peripheralID, characteristicUUID: radarAlertUUID,
            value: Data([0x03, 0x02, 20, 10, 80, 4])
        ))

        let received = await targets.next()
        #expect(received?.count == 2)
        #expect(received?[0].rangeMetres == 20)
        #expect(received?[0].threatLevel == .danger)
        #expect(received?[1].rangeMetres == 80)
    }

    @Test("Unexpected disconnect clears targets, enters reconnecting, retries on backoff ladder")
    func unexpectedDisconnectReconnects() async {
        let harness = Harness()
        let peripheralID = UUID()

        var states = harness.client.connectionState().makeAsyncIterator()
        _ = await states.next()  // .disconnected
        await harness.client.connect(peripheralID)
        _ = await states.next()  // .connecting

        var targets = harness.client.radarTargets().makeAsyncIterator()
        var connects = harness.connectCalls.makeAsyncIterator()
        _ = await connects.next()  // initial connect from connect()

        harness.events.yield(.disconnected(id: peripheralID, error: nil))
        #expect(await targets.next() == [])               // stale vehicles cleared
        #expect(await states.next() == .reconnecting)

        await harness.clock.advance(by: .seconds(1))
        #expect(await connects.next() == peripheralID)    // attempt 1 after 1s
        await harness.clock.advance(by: .seconds(2))
        #expect(await connects.next() == peripheralID)    // attempt 2 after 2s
        await harness.clock.advance(by: .seconds(4))
        #expect(await connects.next() == peripheralID)    // attempt 3 after 4s

        // Reconnection succeeds — backoff task is cancelled.
        harness.events.yield(.connected(id: peripheralID))
        #expect(await states.next() == .connected)

        let countAfterRecovery = harness.connectCount.value
        await harness.clock.advance(by: .seconds(120))
        await Task.yield()
        #expect(harness.connectCount.value == countAfterRecovery)
    }

    @Test("User-initiated disconnect does not trigger reconnection")
    func userDisconnectNoReconnect() async {
        let harness = Harness()
        let peripheralID = UUID()

        var states = harness.client.connectionState().makeAsyncIterator()
        _ = await states.next()
        await harness.client.connect(peripheralID)
        _ = await states.next()  // .connecting

        await harness.client.disconnect()
        #expect(await states.next() == .disconnected)

        // The BLE disconnect event arrives afterwards — target was cleared, so no match.
        harness.events.yield(.disconnected(id: peripheralID, error: nil))
        let countBefore = harness.connectCount.value
        await harness.clock.advance(by: .seconds(120))
        await Task.yield()
        #expect(harness.connectCount.value == countBefore)
    }

    @Test("Discovery of a non-radar peripheral is ignored")
    func nonRadarDiscoveryIgnored() async {
        let harness = Harness()
        let hrStrapID = UUID()
        let radarID = UUID()
        let hrServiceUUID = CBUUID(string: "180D")

        var states = harness.client.connectionState().makeAsyncIterator()
        _ = await states.next()  // .disconnected
        await harness.pair(radarID)
        await harness.client.startScanning()
        _ = await states.next()  // .scanning

        var connects = harness.connectCalls.makeAsyncIterator()

        // An HR strap discovered on the shared central must not be claimed.
        harness.events.yield(.discovered(
            id: hrStrapID, name: "Polar H10", rssi: -50, services: [hrServiceUUID]
        ))
        harness.events.yield(.discovered(
            id: radarID, name: "Varia RTL515", rssi: -60, services: [radarServiceUUID]
        ))

        #expect(await states.next() == .connecting)
        #expect(await connects.next() == radarID)   // first connect is the radar, not the strap
        #expect(harness.connectCount.value == 1)
    }

    @Test("startScanning while connected does not regress connection state")
    func startScanningWhileActiveKeepsState() async {
        let harness = Harness()
        let peripheralID = UUID()

        var states = harness.client.connectionState().makeAsyncIterator()
        _ = await states.next()  // .disconnected
        await harness.pair(peripheralID)
        await harness.client.startScanning()
        _ = await states.next()  // .scanning

        harness.events.yield(.discovered(
            id: peripheralID, name: "Varia RTL515", rssi: -60, services: [radarServiceUUID]
        ))
        _ = await states.next()  // .connecting
        harness.events.yield(.connected(id: peripheralID))
        _ = await states.next()  // .connected
        harness.events.yield(.servicesDiscovered(peripheralID: peripheralID, serviceUUIDs: [radarServiceUUID]))
        harness.events.yield(.characteristicsDiscovered(
            peripheralID: peripheralID, serviceUUID: radarServiceUUID, characteristicUUIDs: [radarAlertUUID]
        ))
        #expect(await states.next() == .active)

        // Re-entry (dashboard .task re-running on view re-appear) must be a no-op.
        let scansBefore = harness.scanned.value.count
        await harness.client.startScanning()
        #expect(harness.scanned.value.count == scansBefore)

        // A fresh subscriber replays the true state, not a stomped .scanning.
        var freshStates = harness.client.connectionState().makeAsyncIterator()
        #expect(await freshStates.next() == .active)
    }

    @Test("Bluetooth permission denied stands down without crashing")
    func permissionDenied() async {
        let harness = Harness()
        let peripheralID = UUID()

        var states = harness.client.connectionState().makeAsyncIterator()
        _ = await states.next()
        await harness.client.connect(peripheralID)
        _ = await states.next()  // .connecting

        harness.events.yield(.stateChanged(.unauthorized))
        #expect(await states.next() == .disconnected)

        // Scanning after denial is a no-op at the transport layer; client must not crash.
        await harness.client.startScanning()
        #expect(await states.next() == .scanning)
    }

    // MARK: Paired-record gate (#97)

    @Test("Two unpaired radars in range: neither is connected, both are listed")
    func unpairedRadarsAreListedButNotConnected() async {
        let harness = Harness()
        let strangerA = UUID()
        let strangerB = UUID()

        await harness.client.startScanning()
        harness.events.yield(.discovered(
            id: strangerA, name: "Varia A", rssi: -50, services: [radarServiceUUID]
        ))
        harness.events.yield(.discovered(
            id: strangerB, name: "Varia B", rssi: -70, services: [radarServiceUUID]
        ))

        let listed = await harness.devices { $0.count == 2 }   // sync point
        #expect(listed.allSatisfy { !$0.isPaired && !$0.isConnected })
        #expect(listed.map(\.name) == ["Varia A", "Varia B"])
        #expect(harness.connectCount.value == 0)

        // Nothing was adopted, so the client is still looking.
        var states = harness.client.connectionState().makeAsyncIterator()
        #expect(await states.next() == .scanning)
    }

    @Test("With one radar paired, a stranger advertising alongside it is listed but not connected")
    func onlyThePairedRadarIsConnected() async {
        let harness = Harness()
        let paired = UUID()
        let stranger = UUID()

        var states = harness.client.connectionState().makeAsyncIterator()
        _ = await states.next()  // .disconnected
        await harness.pair(paired)
        await harness.client.startScanning()
        _ = await states.next()  // .scanning

        // The stranger advertises first — under the old rule it would have been adopted.
        harness.events.yield(.discovered(
            id: stranger, name: "Someone else's Varia", rssi: -40, services: [radarServiceUUID]
        ))
        harness.events.yield(.discovered(
            id: paired, name: "My Varia", rssi: -80, services: [radarServiceUUID]
        ))

        #expect(await states.next() == .connecting)
        #expect(harness.calls.value.contains(.connect(paired)))
        #expect(!harness.calls.value.contains(.connect(stranger)))
        #expect(harness.connectCount.value == 1)

        let listed = await harness.devices { $0.count == 2 }
        #expect(listed.first { $0.id == paired }?.isPaired == true)
        #expect(listed.first { $0.id == stranger }?.isPaired == false)
        // Paired sorts first regardless of advertisement order or name.
        #expect(listed.first?.id == paired)
    }

    @Test("Unpairing disconnects, and the next advertisement does not reconnect")
    func unpairDisconnectsAndDoesNotReadopt() async {
        let harness = Harness()
        let peripheralID = UUID()

        var states = harness.client.connectionState().makeAsyncIterator()
        _ = await states.next()  // .disconnected
        await harness.pair(peripheralID)
        await harness.client.startScanning()
        _ = await states.next()  // .scanning

        harness.events.yield(.discovered(
            id: peripheralID, name: "Varia RTL515", rssi: -60, services: [radarServiceUUID]
        ))
        _ = await states.next()  // .connecting
        harness.events.yield(.connected(id: peripheralID))
        #expect(await states.next() == .connected)

        await harness.pair(nil)
        #expect(await states.next() == .disconnected)

        // One interleaved log, not one spy per endpoint: the point is that nothing
        // reconnects *after* the teardown, which separate counters cannot show.
        #expect(harness.calls.value == [
            .startScanning([radarServiceUUID]),
            .connect(peripheralID),
            .disconnect(peripheralID, "radar"),
        ])

        harness.events.yield(.discovered(
            id: peripheralID, name: "Varia RTL515", rssi: -60, services: [radarServiceUUID]
        ))
        harness.events.yield(.discovered(
            id: peripheralID, name: "Varia RTL515", rssi: -55, services: [radarServiceUUID]
        ))
        _ = await harness.devices { $0.contains { !$0.isPaired } }   // sync point
        #expect(harness.calls.value.filter { $0 == .connect(peripheralID) }.count == 1)

        // The backoff ladder must not resurrect it either.
        await harness.clock.advance(by: .seconds(120))
        await Task.yield()
        #expect(harness.connectCount.value == 1)
    }

    /// CoreBluetooth won't redeliver `.discovered` for a peripheral already seen this
    /// session, so without this path S11's Pair button does nothing until the radar
    /// next advertises.
    @Test("Pairing a radar already seen this session connects it without a new advertisement")
    func pairingConnectsARadarAlreadySeen() async {
        let harness = Harness()
        let peripheralID = UUID()

        var states = harness.client.connectionState().makeAsyncIterator()
        _ = await states.next()  // .disconnected
        await harness.client.startScanning()
        _ = await states.next()  // .scanning

        harness.events.yield(.discovered(
            id: peripheralID, name: "Varia RTL515", rssi: -60, services: [radarServiceUUID]
        ))
        _ = await harness.devices { $0.count == 1 }   // sync point: seen, not connected
        #expect(harness.connectCount.value == 0)

        await harness.pair(peripheralID)
        #expect(await states.next() == .connecting)
        #expect(harness.calls.value.last == .connect(peripheralID))
    }

    @Test("Switching the gate tears the old radar down before connecting the new one")
    func switchingTheGateTearsDownFirst() async {
        let harness = Harness()
        let first = UUID()
        let second = UUID()

        var states = harness.client.connectionState().makeAsyncIterator()
        _ = await states.next()  // .disconnected
        await harness.pair(first)
        await harness.client.startScanning()
        _ = await states.next()  // .scanning

        harness.events.yield(.discovered(id: first, name: "A", rssi: -60, services: [radarServiceUUID]))
        _ = await states.next()  // .connecting
        harness.events.yield(.connected(id: first))
        #expect(await states.next() == .connected)

        // The replacement has been seen, so the switch both disconnects and connects.
        harness.events.yield(.discovered(id: second, name: "B", rssi: -60, services: [radarServiceUUID]))
        _ = await harness.devices { $0.count == 2 }

        await harness.pair(second)
        #expect(await states.next() == .disconnected)
        #expect(await states.next() == .connecting)

        let tail = harness.calls.value.suffix(2)
        #expect(Array(tail) == [.disconnect(first, "radar"), .connect(second)])
    }

    /// Ride finish calls `disconnect()`. If that cleared the pairing too, the radar
    /// would need re-pairing before every ride.
    @Test("Ride-finish disconnect keeps the pairing")
    func rideFinishDisconnectKeepsThePairing() async {
        let harness = Harness()
        let peripheralID = UUID()

        var states = harness.client.connectionState().makeAsyncIterator()
        _ = await states.next()  // .disconnected
        await harness.pair(peripheralID)
        await harness.client.startScanning()
        _ = await states.next()  // .scanning

        harness.events.yield(.discovered(
            id: peripheralID, name: "Varia RTL515", rssi: -60, services: [radarServiceUUID]
        ))
        _ = await states.next()  // .connecting
        harness.events.yield(.connected(id: peripheralID))
        _ = await states.next()  // .connected

        await harness.client.disconnect()
        #expect(await states.next() == .disconnected)

        // Next ride.
        await harness.client.startScanning()
        _ = await states.next()  // .scanning
        harness.events.yield(.discovered(
            id: peripheralID, name: "Varia RTL515", rssi: -60, services: [radarServiceUUID]
        ))
        #expect(await states.next() == .connecting)
        #expect(harness.connectCount.value == 2)
    }

    /// The rider didn't unpair — the radio went off.
    @Test("Standing down for a permission denial keeps the pairing")
    func permissionDenialKeepsThePairing() async {
        let harness = Harness()
        let peripheralID = UUID()

        var states = harness.client.connectionState().makeAsyncIterator()
        _ = await states.next()  // .disconnected
        await harness.pair(peripheralID)
        await harness.client.connect(peripheralID)
        _ = await states.next()  // .connecting

        harness.events.yield(.stateChanged(.unauthorized))
        #expect(await states.next() == .disconnected)

        await harness.client.startScanning()
        _ = await states.next()  // .scanning
        harness.events.yield(.discovered(
            id: peripheralID, name: "Varia RTL515", rssi: -60, services: [radarServiceUUID]
        ))
        #expect(await states.next() == .connecting)
    }

    @Test("A late discovery subscriber gets the current device list replayed")
    func discoveredDevicesReplaysForALateSubscriber() async {
        let harness = Harness()
        let peripheralID = UUID()

        await harness.client.startScanning()
        harness.events.yield(.discovered(
            id: peripheralID, name: "Varia RTL515", rssi: -60, services: [radarServiceUUID]
        ))
        _ = await harness.devices { $0.count == 1 }   // sync point

        var late = harness.client.discoveredDevices().makeAsyncIterator()
        let replayed = await late.next()
        #expect(replayed?.map(\.id) == [peripheralID])
        #expect(replayed?.first?.name == "Varia RTL515")
    }
    // MARK: - Pairing scan (S11, #98)

    /// The Sensors screen holds one pairing scan open per client. Radar's ambient
    /// `startScanning` refuses once anything is connected — deliberately, so a
    /// re-entered dashboard `.task` can't stomp a live connection back to `.scanning`
    /// — which is exactly the guard a pairing scan has to get past.
    @Test("Pairing scan runs even with a radar already connected")
    func pairingScanBypassesColdStateGuard() async {
        let harness = Harness()
        let id = UUID()
        var states = harness.client.connectionState().makeAsyncIterator()
        #expect(await states.next() == .disconnected)

        await harness.pair(id)
        await harness.client.startScanning()
        #expect(await states.next() == .scanning)
        harness.events.yield(.discovered(id: id, name: "Varia", rssi: -60, services: [radarServiceUUID]))
        #expect(await states.next() == .connecting)
        harness.events.yield(.connected(id: id))
        #expect(await states.next() == .connected)

        harness.scanned.withValue { $0.removeAll() }
        await harness.client.startScanning()
        #expect(harness.scanned.value.isEmpty)   // ambient guard holds

        await harness.client.beginPairingScan()
        #expect(harness.scanned.value == [[radarServiceUUID]])
    }

    @Test("A pairing scan does not move the radar's connection state")
    func pairingScanDoesNotAffectConnectionState() async {
        let harness = Harness()
        let id = UUID()
        var states = harness.client.connectionState().makeAsyncIterator()
        #expect(await states.next() == .disconnected)

        await harness.pair(id)
        await harness.client.beginPairingScan()
        harness.events.yield(.discovered(id: id, name: "Varia", rssi: -60, services: [radarServiceUUID]))

        // `.connecting` because the gate admitted it — never `.scanning`, which would
        // read as "Searching" on the ride sidebar behind a settings screen.
        #expect(await states.next() == .connecting)
    }

    @Test("Ending a pairing scan leaves the ambient dashboard scan running")
    func endPairingScanRespectsAmbientScan() async {
        let harness = Harness()
        await harness.client.startScanning()      // ambient, from a cold state
        await harness.client.beginPairingScan()

        await harness.client.endPairingScan()
        #expect(!harness.calls.value.contains(.stopScanning([radarServiceUUID])))

        // ...and the ambient stop is likewise deferred while a pairing scan is open.
        await harness.client.beginPairingScan()
        await harness.client.stopScanning()
        #expect(!harness.calls.value.contains(.stopScanning([radarServiceUUID])))

        await harness.client.endPairingScan()
        #expect(harness.calls.value.last == .stopScanning([radarServiceUUID]))
    }

    /// The one that bites. `BLEClient.requestedServices` is a plain set with no
    /// per-caller refcount, so ride finish releasing the radar UUID would silently
    /// blind an open Sensors screen.
    @Test("Finishing a ride does not kill an open pairing scan")
    func disconnectRespectsPairingScan() async {
        let harness = Harness()
        let id = UUID()
        await harness.pair(id)
        await harness.client.startScanning()
        harness.events.yield(.discovered(id: id, name: "Varia", rssi: -60, services: [radarServiceUUID]))
        _ = await harness.devices { $0.contains { $0.id == id } }

        await harness.client.beginPairingScan()
        await harness.client.disconnect()
        #expect(!harness.calls.value.contains(.stopScanning([radarServiceUUID])))

        await harness.client.endPairingScan()
        #expect(harness.calls.value.last == .stopScanning([radarServiceUUID]))
    }

    @Test("A pairing scan re-issues the hardware scan, which is what refresh restarts")
    func pairingScanReissuesTheScan() async {
        let harness = Harness()
        await harness.client.beginPairingScan()
        await harness.client.beginPairingScan()
        #expect(harness.scanned.value == [[radarServiceUUID], [radarServiceUUID]])

        // Balanced back down to one holder: the radio stays up.
        await harness.client.endPairingScan()
        #expect(!harness.calls.value.contains(.stopScanning([radarServiceUUID])))
    }

    /// The reported bug: a radar switched off stayed in Available for the life of the
    /// process, because `discoveredIDs` was never pruned.
    @Test("A radar that stops advertising leaves the list on the next sweep")
    func staleRadarIsSweptAway() async {
        let harness = Harness()
        let staying = UUID()
        let leaving = UUID()

        await harness.client.beginPairingScan()
        harness.events.yield(.discovered(id: staying, name: "Varia A", rssi: -60, services: [radarServiceUUID]))
        harness.events.yield(.discovered(id: leaving, name: "Varia B", rssi: -70, services: [radarServiceUUID]))
        _ = await harness.devices { $0.count == 2 }

        // Rotate the generation, then let only A re-advertise. The name change is the
        // sync point: events are handled on the client's own task, and `count == 2` is
        // already true here, so it would prove nothing about A's report having landed —
        // and rotating again too early would sweep A away with B.
        await harness.client.beginPairingScan()
        harness.events.yield(.discovered(id: staying, name: "Varia A2", rssi: -60, services: [radarServiceUUID]))
        _ = await harness.devices { list in
            list.first { $0.id == staying }?.name == "Varia A2"
        }

        // B stayed silent through that whole generation, so this sweep drops it.
        await harness.client.beginPairingScan()

        let devices = await harness.devices { $0.map(\.id) == [staying] }
        #expect(devices.map(\.name) == ["Varia A2"])
    }

    /// A connected peripheral stops advertising — that is normal BLE behaviour, not a
    /// sign it has gone. Sweeping it would delete the row for the radar in use.
    @Test("A connected radar survives a sweep even though it stops advertising")
    func connectedRadarSurvivesSweep() async {
        let harness = Harness()
        let id = UUID()
        await harness.pair(id)

        var states = harness.client.connectionState().makeAsyncIterator()
        #expect(await states.next() == .disconnected)
        await harness.client.beginPairingScan()
        harness.events.yield(.discovered(id: id, name: "Varia RTL515", rssi: -60, services: [radarServiceUUID]))
        #expect(await states.next() == .connecting)
        harness.events.yield(.connected(id: id))
        #expect(await states.next() == .connected)

        // Two full generations with no advertisement at all.
        await harness.client.beginPairingScan()
        await harness.client.beginPairingScan()

        let devices = await harness.devices { $0.count == 1 }
        #expect(devices[0].id == id)
        #expect(devices[0].name == "Varia RTL515")
    }

    @Test("Discovery rows carry the radar tag, its role and its lifecycle")
    func discoveryRowsAreTagged() async {
        let harness = Harness()
        let paired = UUID()
        let stranger = UUID()
        await harness.pair(paired)

        harness.events.yield(.discovered(id: stranger, name: "Someone else's Varia", rssi: -70, services: [radarServiceUUID]))
        harness.events.yield(.discovered(id: paired, name: "Varia RTL515", rssi: -60, services: [radarServiceUUID]))
        harness.events.yield(.connected(id: paired))
        harness.events.yield(.servicesDiscovered(peripheralID: paired, serviceUUIDs: [radarServiceUUID]))
        harness.events.yield(.characteristicsDiscovered(
            peripheralID: paired, serviceUUID: radarServiceUUID, characteristicUUIDs: [radarAlertUUID]
        ))

        let devices = await harness.devices { list in
            list.first { $0.id == paired }?.connectionState == .active && list.count == 2
        }
        let mine = devices.first { $0.id == paired }!
        #expect(mine.kinds == [.radar])
        #expect(mine.roles == [.radar])
        #expect(mine.isPaired)

        let theirs = devices.first { $0.id == stranger }!
        #expect(theirs.kinds == [.radar])
        #expect(theirs.roles.isEmpty)
        // Nothing is tracked about a radar this client will not adopt, so it has no
        // lifecycle to report — not even `.disconnected`.
        #expect(theirs.connectionState == nil)
    }
}

// MARK: - Test value

@Suite("VariaRadarClient — test value")
struct VariaRadarTestValueTests {

    @Test("Test value methods do not crash")
    func methodsNoOp() async {
        let client = VariaRadarClient.testValue
        await client.startScanning()
        await client.stopScanning()
        await client.connect(UUID())
        await client.disconnect()
        await client.setPairedSensor(UUID())
        await client.setPairedSensor(nil)
        await client.beginPairingScan()
        await client.endPairingScan()
    }

    @Test("Test value streams complete immediately")
    func streamsComplete() async {
        let client = VariaRadarClient.testValue
        var targetCount = 0
        for await _ in client.radarTargets() { targetCount += 1 }
        #expect(targetCount == 0)
        var stateCount = 0
        for await _ in client.connectionState() { stateCount += 1 }
        #expect(stateCount == 0)
    }
}
