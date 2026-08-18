import Foundation
import Testing
import ComposableArchitecture
import CoreBluetooth
@testable import Cyclometer

private let hrServiceUUID      = CBUUID(string: "180D")
private let hrMeasurementUUID  = CBUUID(string: "2A37")
private let batteryServiceUUID = CBUUID(string: "180F")
private let batteryLevelUUID   = CBUUID(string: "2A19")

@Suite("BLEHRClient")
struct BLEHRClientTests {

    // MARK: - BPM parsing

    @Test("uint8 BPM: flags 0x00 means value in byte 1")
    func parseBPMUInt8() {
        let data = Data([0x00, 75])
        #expect(BLEHRClient.parseBPM(from: data) == 75)
    }

    @Test("uint8 BPM: flags with other bits set, bit 0 clear still reads byte 1")
    func parseBPMUInt8OtherFlagBits() {
        let data = Data([0x04, 142])  // bit 2 set (energy expended), bit 0 clear → uint8
        #expect(BLEHRClient.parseBPM(from: data) == 142)
    }

    @Test("uint16 BPM: flags 0x01 means little-endian value in bytes 1-2")
    func parseBPMUInt16() {
        // 180 bpm = 0x00B4; LE bytes: 0xB4, 0x00
        let data = Data([0x01, 0xB4, 0x00])
        #expect(BLEHRClient.parseBPM(from: data) == 180)
    }

    @Test("uint16 BPM: high byte contributes to value")
    func parseBPMUInt16HighByte() {
        // 300 bpm = 0x012C; LE bytes: 0x2C, 0x01
        let data = Data([0x01, 0x2C, 0x01])
        #expect(BLEHRClient.parseBPM(from: data) == 300)
    }

    @Test("returns nil when data is empty")
    func parseBPMEmpty() {
        #expect(BLEHRClient.parseBPM(from: Data()) == nil)
    }

    @Test("returns nil when data has only flags byte")
    func parseBPMOneByte() {
        #expect(BLEHRClient.parseBPM(from: Data([0x00])) == nil)
    }

    @Test("returns nil for uint16 format with only 2 bytes total")
    func parseBPMUInt16TooShort() {
        let data = Data([0x01, 0xB4])  // uint16 flag but missing second value byte
        #expect(BLEHRClient.parseBPM(from: data) == nil)
    }

    @Test("uint8 parsing ignores trailing bytes beyond byte 1")
    func parseBPMUInt8IgnoresTrailing() {
        let data = Data([0x00, 95, 0xFF, 0xFF])
        #expect(BLEHRClient.parseBPM(from: data) == 95)
    }

    // MARK: - testValue behaviour

    @Test("testValue startScanning does not crash")
    func testValueStartScanning() async {
        let client = BLEHRClient.testValue
        await client.startScanning()
    }

    @Test("testValue stopScanning does not crash")
    func testValueStopScanning() async {
        let client = BLEHRClient.testValue
        await client.stopScanning()
    }

    @Test("testValue connect does not crash")
    func testValueConnect() async {
        let client = BLEHRClient.testValue
        await client.connect(UUID())
    }

    @Test("testValue disconnect does not crash")
    func testValueDisconnect() async {
        let client = BLEHRClient.testValue
        await client.disconnect()
    }

    @Test("testValue setPairedSensor does not crash")
    func testValueSetPairedSensor() async {
        let client = BLEHRClient.testValue
        await client.setPairedSensor(UUID())
        await client.setPairedSensor(nil)
    }

    @Test("testValue discoveredDevices stream completes immediately")
    func testValueDiscoveredDevicesStream() async {
        let client = BLEHRClient.testValue
        var count = 0
        for await _ in client.discoveredDevices() { count += 1 }
        #expect(count == 0)
    }

    @Test("testValue heartRate stream completes immediately")
    func testValueHeartRateStream() async {
        let client = BLEHRClient.testValue
        var count = 0
        for await _ in client.heartRate() { count += 1 }
        #expect(count == 0)
    }

    @Test("testValue pairingStatus stream completes immediately")
    func testValuePairingStream() async {
        let client = BLEHRClient.testValue
        var count = 0
        for await _ in client.pairingStatus() { count += 1 }
        #expect(count == 0)
    }

    @Test("testValue batteryLevel stream completes immediately")
    func testValueBatteryStream() async {
        let client = BLEHRClient.testValue
        var count = 0
        for await _ in client.batteryLevel() { count += 1 }
        #expect(count == 0)
    }
}

// MARK: - Integration (controllable BLEClient)

/// Time-limited for the same reason as the radar suite: these assertions await broadcast
/// streams that never finish, so a missing emission would hang rather than fail.
@Suite("BLEHRClient — live state machine", .timeLimit(.minutes(1)))
struct BLEHRIntegrationTests {

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

    /// Controllable transport: events are injected by the test, every operation is
    /// recorded. No clock — unlike the radar and CSC clients, the HR client has no
    /// reconnect backoff to drive; rescanning after a drop is its reconnect.
    private struct Harness {
        let client: BLEHRClient
        let events: AsyncStream<BLEEvent>.Continuation
        let servicesDiscovered: LockIsolated<[[CBUUID]?]>
        let notified: LockIsolated<[(Bool, CBUUID)]>
        let reads: LockIsolated<[CBUUID]>
        let calls: LockIsolated<[BLECall]>

        init() {
            let (eventStream, eventContinuation) = AsyncStream<BLEEvent>.makeStream()
            let servicesDiscovered = LockIsolated<[[CBUUID]?]>([])
            let notified = LockIsolated<[(Bool, CBUUID)]>([])
            let reads = LockIsolated<[CBUUID]>([])
            let calls = LockIsolated<[BLECall]>([])

            let bleClient = BLEClient(
                startScanning: { uuids in calls.withValue { $0.append(.startScanning(uuids)) } },
                stopScanning: { uuids in calls.withValue { $0.append(.stopScanning(uuids)) } },
                connect: { id, _ in calls.withValue { $0.append(.connect(id)) } },
                disconnect: { id, owner in calls.withValue { $0.append(.disconnect(id, owner)) } },
                discoverServices: { _, uuids in
                    servicesDiscovered.withValue { $0.append(uuids) }
                },
                discoverCharacteristics: { _, _, _ in },
                setNotifyValue: { enabled, _, _, charUUID in
                    notified.withValue { $0.append((enabled, charUUID)) }
                },
                readValue: { _, _, charUUID in reads.withValue { $0.append(charUUID) } },
                events: { eventStream },
                authorization: { .allowedAlways },
                requestAuthorization: { .allowedAlways }
            )

            self.client = BLEHRClient.live(bleClient: bleClient)
            self.events = eventContinuation
            self.servicesDiscovered = servicesDiscovered
            self.notified = notified
            self.reads = reads
            self.calls = calls
        }

        /// Tell the client this strap is paired, the way `AppFeature` does at launch.
        func pair(_ id: UUID?) async {
            await client.setPairedSensor(id)
        }

        /// Drive a discovered strap all the way to notifying.
        func bringToPaired(_ id: UUID, name: String = "HRM-Dual") {
            events.yield(.discovered(id: id, name: name, rssi: -55, services: [hrServiceUUID]))
            events.yield(.connected(id: id))
            events.yield(.servicesDiscovered(peripheralID: id, serviceUUIDs: [hrServiceUUID]))
            events.yield(.characteristicsDiscovered(
                peripheralID: id, serviceUUID: hrServiceUUID, characteristicUUIDs: [hrMeasurementUUID]
            ))
        }

        /// Wait until the device list satisfies `predicate`, and return it.
        ///
        /// Events are handled on the client's own task, so yielding one and reading the
        /// list on the next line is a race. Tests that assert on pairing status get a
        /// sync point for free from that stream; device-list assertions need this.
        func devices(
            matching predicate: @Sendable ([DiscoveredDevice]) -> Bool
        ) async -> [DiscoveredDevice] {
            for await list in client.discoveredDevices() where predicate(list) { return list }
            return []
        }
    }

    @Test("Discovery pairs the strap and subscribes to measurements")
    func discoveryPairs() async {
        let harness = Harness()
        let id = UUID()

        var paired = harness.client.pairingStatus().makeAsyncIterator()
        #expect(await paired.next() == false)   // replayed: nothing paired yet

        await harness.pair(id)
        harness.bringToPaired(id)

        #expect(await paired.next() == true)
        #expect(harness.notified.value.contains { $0.0 && $0.1 == hrMeasurementUUID })
    }

    /// The Start sheet hides unpaired rows, so without replay a strap that paired
    /// before the sheet opened would show no row — and therefore no battery.
    @Test("A late pairing subscriber gets the current state replayed")
    func pairingReplaysForLateSubscriber() async {
        let harness = Harness()
        let id = UUID()

        var early = harness.client.pairingStatus().makeAsyncIterator()
        _ = await early.next()

        await harness.pair(id)
        harness.bringToPaired(id)
        #expect(await early.next() == true)   // sync point

        var late = harness.client.pairingStatus().makeAsyncIterator()
        #expect(await late.next() == true)
    }

    @Test("Connecting discovers the battery service alongside the HR service")
    func connectDiscoversBatteryService() async {
        let harness = Harness()
        let id = UUID()

        var paired = harness.client.pairingStatus().makeAsyncIterator()
        _ = await paired.next()

        await harness.pair(id)
        harness.bringToPaired(id)
        #expect(await paired.next() == true)   // sync point: discoverServices has run

        #expect(harness.servicesDiscovered.value.count == 1)
        #expect(harness.servicesDiscovered.value[0]?.contains(hrServiceUUID) == true)
        #expect(harness.servicesDiscovered.value[0]?.contains(batteryServiceUUID) == true)
    }

    @Test("Battery level is read on connect and published, then cleared on disconnect")
    func batteryLevelReadAndCleared() async {
        let harness = Harness()
        let id = UUID()

        var battery = harness.client.batteryLevel().makeAsyncIterator()
        #expect(await battery.next() == Int?.none)   // replayed: nothing read yet

        await harness.pair(id)
        harness.events.yield(.discovered(id: id, name: "HRM-Dual", rssi: -55, services: [hrServiceUUID]))
        harness.events.yield(.connected(id: id))
        harness.events.yield(.servicesDiscovered(
            peripheralID: id, serviceUUIDs: [hrServiceUUID, batteryServiceUUID]
        ))
        harness.events.yield(.characteristicsDiscovered(
            peripheralID: id, serviceUUID: batteryServiceUUID,
            characteristicUUIDs: [batteryLevelUUID]
        ))
        // Stands in for the peripheral answering the read.
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: id, characteristicUUID: batteryLevelUUID, value: Data([0x2D])
        ))

        #expect(await battery.next() == 45)
        #expect(harness.reads.value == [batteryLevelUUID])

        harness.events.yield(.disconnected(id: id, error: nil))
        #expect(await battery.next() == Int?.none)
    }

    /// A rider finishing a ride calls `disconnect()`, which nils the target before the
    /// `.disconnected` event arrives — so that event's clearing branch guard-fails and
    /// never runs. Without clearing here, the next Start sheet replays "paired, 45%"
    /// for a strap that is powered off.
    @Test("User disconnect clears pairing and battery for later subscribers")
    func userDisconnectClearsReplayedState() async {
        let harness = Harness()
        let id = UUID()

        var paired = harness.client.pairingStatus().makeAsyncIterator()
        _ = await paired.next()

        await harness.pair(id)
        harness.events.yield(.discovered(id: id, name: "HRM-Dual", rssi: -55, services: [hrServiceUUID]))
        harness.events.yield(.connected(id: id))
        harness.events.yield(.servicesDiscovered(
            peripheralID: id, serviceUUIDs: [hrServiceUUID, batteryServiceUUID]
        ))
        harness.events.yield(.characteristicsDiscovered(
            peripheralID: id, serviceUUID: hrServiceUUID, characteristicUUIDs: [hrMeasurementUUID]
        ))
        harness.events.yield(.characteristicsDiscovered(
            peripheralID: id, serviceUUID: batteryServiceUUID, characteristicUUIDs: [batteryLevelUUID]
        ))
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: id, characteristicUUID: batteryLevelUUID, value: Data([0x2D])
        ))
        #expect(await paired.next() == true)   // sync point: fully connected

        await harness.client.disconnect()
        // The transport answers after the fact, as it does on hardware.
        harness.events.yield(.disconnected(id: id, error: nil))

        var latePaired = harness.client.pairingStatus().makeAsyncIterator()
        var lateBattery = harness.client.batteryLevel().makeAsyncIterator()
        #expect(await latePaired.next() == false)
        #expect(await lateBattery.next() == Int?.none)
    }

    /// The strap keeps notifying BPM whatever the battery does; a battery frame must
    /// not be mistaken for a measurement, or vice versa.
    @Test("Battery and heart-rate values stay on their own streams")
    func batteryDoesNotDisturbHeartRate() async {
        let harness = Harness()
        let id = UUID()

        var paired = harness.client.pairingStatus().makeAsyncIterator()
        _ = await paired.next()
        await harness.pair(id)
        harness.bringToPaired(id)
        #expect(await paired.next() == true)

        var bpms = harness.client.heartRate().makeAsyncIterator()
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: id, characteristicUUID: batteryLevelUUID, value: Data([0x50])
        ))
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: id, characteristicUUID: hrMeasurementUUID, value: Data([0x00, 142])
        ))

        #expect(await bpms.next() == 142)   // the battery frame produced no BPM
    }

    // MARK: Paired-record gate (#97)

    @Test("Two unpaired straps in range: neither is connected, both are listed")
    func unpairedStrapsAreListedButNotConnected() async {
        let harness = Harness()
        let strangerA = UUID()
        let strangerB = UUID()

        await harness.client.startScanning()
        harness.events.yield(.discovered(id: strangerA, name: "Strap A", rssi: -50, services: [hrServiceUUID]))
        harness.events.yield(.discovered(id: strangerB, name: "Strap B", rssi: -70, services: [hrServiceUUID]))

        let listed = await harness.devices { $0.count == 2 }   // sync point
        #expect(listed.allSatisfy { !$0.isPaired && !$0.isConnected })
        #expect(listed.map(\.name) == ["Strap A", "Strap B"])
        #expect(!harness.calls.value.contains { if case .connect = $0 { true } else { false } })
    }

    @Test("With one strap paired, a training partner's strap is listed but not connected")
    func onlyThePairedStrapIsConnected() async {
        let harness = Harness()
        let paired = UUID()
        let stranger = UUID()

        var status = harness.client.pairingStatus().makeAsyncIterator()
        _ = await status.next()

        await harness.pair(paired)
        await harness.client.startScanning()

        // The stranger advertises first — under the old rule it would have been adopted.
        harness.events.yield(.discovered(id: stranger, name: "Partner", rssi: -40, services: [hrServiceUUID]))
        harness.bringToPaired(paired, name: "Mine")
        #expect(await status.next() == true)   // sync point

        #expect(harness.calls.value.contains(.connect(paired)))
        #expect(!harness.calls.value.contains(.connect(stranger)))

        let listed = await harness.devices { $0.count == 2 }
        #expect(listed.first?.id == paired)               // paired sorts first
        #expect(listed.first?.isConnected == true)
        #expect(listed.last?.isPaired == false)
    }

    @Test("Unpairing disconnects, and the next advertisement does not reconnect")
    func unpairDisconnectsAndDoesNotReadopt() async {
        let harness = Harness()
        let id = UUID()

        var status = harness.client.pairingStatus().makeAsyncIterator()
        _ = await status.next()
        await harness.pair(id)
        await harness.client.startScanning()
        harness.bringToPaired(id)
        #expect(await status.next() == true)

        await harness.pair(nil)
        #expect(await status.next() == false)

        // One interleaved log, not one spy per endpoint: the point is that nothing
        // reconnects *after* the teardown, which separate counters cannot show.
        #expect(harness.calls.value == [
            .startScanning([hrServiceUUID]),
            .connect(id),
            .disconnect(id, "hr"),
        ])

        // The transport answers after the fact, as it does on hardware. The target was
        // already cleared, so this must not restart the scan either.
        harness.events.yield(.disconnected(id: id, error: nil))
        harness.events.yield(.discovered(id: id, name: "HRM-Dual", rssi: -55, services: [hrServiceUUID]))
        harness.events.yield(.discovered(id: id, name: "HRM-Dual", rssi: -50, services: [hrServiceUUID]))
        _ = await harness.devices { $0.contains { !$0.isPaired } }   // sync point

        #expect(harness.calls.value.filter { $0 == .connect(id) }.count == 1)
        #expect(harness.calls.value.filter { $0 == .startScanning([hrServiceUUID]) }.count == 1)
    }

    /// CoreBluetooth won't redeliver `.discovered` for a peripheral already seen this
    /// session, so without this path S11's Pair button does nothing until the strap
    /// next advertises.
    @Test("Pairing a strap already seen this session connects it without a new advertisement")
    func pairingConnectsAStrapAlreadySeen() async {
        let harness = Harness()
        let id = UUID()

        await harness.client.startScanning()
        harness.events.yield(.discovered(id: id, name: "HRM-Dual", rssi: -55, services: [hrServiceUUID]))
        _ = await harness.devices { $0.count == 1 }   // sync point: seen, not connected
        #expect(!harness.calls.value.contains(.connect(id)))

        await harness.pair(id)
        #expect(harness.calls.value.last == .connect(id))
    }

    @Test("Switching the gate tears the old strap down before connecting the new one")
    func switchingTheGateTearsDownFirst() async {
        let harness = Harness()
        let first = UUID()
        let second = UUID()

        var status = harness.client.pairingStatus().makeAsyncIterator()
        _ = await status.next()
        await harness.pair(first)
        await harness.client.startScanning()
        harness.bringToPaired(first, name: "A")
        #expect(await status.next() == true)

        // The replacement has been seen, so the switch both disconnects and connects.
        harness.events.yield(.discovered(id: second, name: "B", rssi: -55, services: [hrServiceUUID]))
        _ = await harness.devices { $0.count == 2 }

        await harness.pair(second)
        #expect(await status.next() == false)

        let tail = harness.calls.value.suffix(2)
        #expect(Array(tail) == [.disconnect(first, "hr"), .connect(second)])
    }

    /// Rescanning *is* this client's reconnect — it has no backoff ladder. Once gated,
    /// the rescan can no longer adopt whoever advertises first.
    @Test("An unexpected drop rescans and readmits only the paired strap")
    func unexpectedDropReadmitsOnlyThePairedStrap() async {
        let harness = Harness()
        let paired = UUID()
        let stranger = UUID()

        var status = harness.client.pairingStatus().makeAsyncIterator()
        _ = await status.next()
        await harness.pair(paired)
        await harness.client.startScanning()
        harness.bringToPaired(paired)
        #expect(await status.next() == true)

        harness.events.yield(.disconnected(id: paired, error: nil))
        #expect(await status.next() == false)
        #expect(harness.calls.value.filter { $0 == .startScanning([hrServiceUUID]) }.count == 2)

        // The rescan redelivers everything in range. Only the paired strap gets back in.
        harness.events.yield(.discovered(id: stranger, name: "Partner", rssi: -40, services: [hrServiceUUID]))
        harness.bringToPaired(paired)
        #expect(await status.next() == true)

        #expect(!harness.calls.value.contains(.connect(stranger)))
        #expect(harness.calls.value.filter { $0 == .connect(paired) }.count == 2)
    }

    /// An explicit `connect(_:)` selection that drops has no record behind it, so
    /// rescanning would leave the radio looking for a strap the gate would refuse.
    @Test("A drop with nothing paired does not restart the scan")
    func dropWithNothingPairedDoesNotRescan() async {
        let harness = Harness()
        let id = UUID()

        var status = harness.client.pairingStatus().makeAsyncIterator()
        _ = await status.next()

        await harness.client.connect(id)
        harness.events.yield(.connected(id: id))
        harness.events.yield(.servicesDiscovered(peripheralID: id, serviceUUIDs: [hrServiceUUID]))
        harness.events.yield(.characteristicsDiscovered(
            peripheralID: id, serviceUUID: hrServiceUUID, characteristicUUIDs: [hrMeasurementUUID]
        ))
        #expect(await status.next() == true)

        harness.events.yield(.disconnected(id: id, error: nil))
        #expect(await status.next() == false)

        #expect(!harness.calls.value.contains(.startScanning([hrServiceUUID])))
    }

    /// A ride that finished with no strap connected still has to stop the scan, or the
    /// radio keeps looking for a strap this client will now refuse to adopt anyway.
    @Test("Disconnect stops the scan even when nothing was connected")
    func disconnectStopsTheScanWithNothingConnected() async {
        let harness = Harness()

        await harness.client.startScanning()
        await harness.client.disconnect()

        #expect(harness.calls.value == [
            .startScanning([hrServiceUUID]),
            .stopScanning([hrServiceUUID]),
        ])
    }

    /// Ride finish calls `disconnect()`. If that cleared the pairing too, the strap
    /// would need re-pairing before every ride.
    @Test("Ride-finish disconnect keeps the pairing")
    func rideFinishDisconnectKeepsThePairing() async {
        let harness = Harness()
        let id = UUID()

        var status = harness.client.pairingStatus().makeAsyncIterator()
        _ = await status.next()
        await harness.pair(id)
        await harness.client.startScanning()
        harness.bringToPaired(id)
        #expect(await status.next() == true)

        await harness.client.disconnect()
        #expect(await status.next() == false)
        harness.events.yield(.disconnected(id: id, error: nil))

        // Next ride.
        await harness.client.startScanning()
        harness.bringToPaired(id)
        #expect(await status.next() == true)
        #expect(harness.calls.value.filter { $0 == .connect(id) }.count == 2)
    }

    @Test("A late discovery subscriber gets the current device list replayed")
    func discoveredDevicesReplaysForALateSubscriber() async {
        let harness = Harness()
        let id = UUID()

        await harness.client.startScanning()
        harness.events.yield(.discovered(id: id, name: "HRM-Dual", rssi: -55, services: [hrServiceUUID]))
        _ = await harness.devices { $0.count == 1 }   // sync point

        var late = harness.client.discoveredDevices().makeAsyncIterator()
        let replayed = await late.next()
        #expect(replayed?.map(\.id) == [id])
        #expect(replayed?.first?.name == "HRM-Dual")
    }
}
