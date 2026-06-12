import Testing
import ComposableArchitecture
import CoreBluetooth
@testable import Cyclometer

private let radarServiceUUID = CBUUID(string: "6A4E3200-667B-11E3-949A-0800200C9A66")
private let radarAlertUUID   = CBUUID(string: "6A4E3202-667B-11E3-949A-0800200C9A66")

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

@Suite("VariaRadarClient — live state machine")
struct VariaRadarIntegrationTests {

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
        let clock: TestClock<Duration>

        init() {
            let (eventStream, eventContinuation) = AsyncStream<BLEEvent>.makeStream()
            let (connectStream, connectContinuation) = AsyncStream<UUID>.makeStream()
            let connectCount = LockIsolated(0)
            let scanned = LockIsolated<[[CBUUID]]>([])
            let notified = LockIsolated<[(Bool, CBUUID)]>([])
            let clock = TestClock()

            let bleClient = BLEClient(
                startScanning: { uuids in scanned.withValue { $0.append(uuids) } },
                stopScanning: { _ in },
                connect: { id in
                    connectCount.withValue { $0 += 1 }
                    connectContinuation.yield(id)
                },
                disconnect: { _ in },
                discoverServices: { _, _ in },
                discoverCharacteristics: { _, _, _ in },
                setNotifyValue: { enabled, _, _, charUUID in
                    notified.withValue { $0.append((enabled, charUUID)) }
                },
                events: { eventStream }
            )

            self.client = VariaRadarClient.live(bleClient: bleClient, clock: clock)
            self.events = eventContinuation
            self.connectCalls = connectStream
            self.connectCount = connectCount
            self.scanned = scanned
            self.notified = notified
            self.clock = clock
        }
    }

    @Test("Discovery sequence drives state machine to active and enables notifications")
    func discoveryToActive() async {
        let harness = Harness()
        let peripheralID = UUID()

        var states = harness.client.connectionState().makeAsyncIterator()
        #expect(await states.next() == .disconnected)  // replayed current state

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
