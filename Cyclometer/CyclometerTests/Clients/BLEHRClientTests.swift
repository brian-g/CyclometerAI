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

@Suite("BLEHRClient — live state machine")
struct BLEHRIntegrationTests {

    /// Controllable transport: events are injected by the test, every operation is
    /// recorded. No clock — unlike the radar and CSC clients, the HR client has no
    /// reconnect backoff to drive.
    private struct Harness {
        let client: BLEHRClient
        let events: AsyncStream<BLEEvent>.Continuation
        let servicesDiscovered: LockIsolated<[[CBUUID]?]>
        let notified: LockIsolated<[(Bool, CBUUID)]>
        let reads: LockIsolated<[CBUUID]>

        init() {
            let (eventStream, eventContinuation) = AsyncStream<BLEEvent>.makeStream()
            let servicesDiscovered = LockIsolated<[[CBUUID]?]>([])
            let notified = LockIsolated<[(Bool, CBUUID)]>([])
            let reads = LockIsolated<[CBUUID]>([])

            let bleClient = BLEClient(
                startScanning: { _ in },
                stopScanning: { _ in },
                connect: { _, _ in },
                disconnect: { _, _ in },
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
        }
    }

    @Test("Discovery pairs the strap and subscribes to measurements")
    func discoveryPairs() async {
        let harness = Harness()
        let id = UUID()

        var paired = harness.client.pairingStatus().makeAsyncIterator()
        #expect(await paired.next() == false)   // replayed: nothing paired yet

        harness.events.yield(.discovered(id: id, name: "HRM-Dual", rssi: -55, services: [hrServiceUUID]))
        harness.events.yield(.connected(id: id))
        harness.events.yield(.servicesDiscovered(peripheralID: id, serviceUUIDs: [hrServiceUUID]))
        harness.events.yield(.characteristicsDiscovered(
            peripheralID: id, serviceUUID: hrServiceUUID, characteristicUUIDs: [hrMeasurementUUID]
        ))

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

        harness.events.yield(.discovered(id: id, name: "HRM-Dual", rssi: -55, services: [hrServiceUUID]))
        harness.events.yield(.connected(id: id))
        harness.events.yield(.servicesDiscovered(peripheralID: id, serviceUUIDs: [hrServiceUUID]))
        harness.events.yield(.characteristicsDiscovered(
            peripheralID: id, serviceUUID: hrServiceUUID, characteristicUUIDs: [hrMeasurementUUID]
        ))
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

        harness.events.yield(.discovered(id: id, name: "HRM-Dual", rssi: -55, services: [hrServiceUUID]))
        harness.events.yield(.connected(id: id))
        harness.events.yield(.servicesDiscovered(peripheralID: id, serviceUUIDs: [hrServiceUUID]))
        harness.events.yield(.characteristicsDiscovered(
            peripheralID: id, serviceUUID: hrServiceUUID, characteristicUUIDs: [hrMeasurementUUID]
        ))
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
        harness.events.yield(.discovered(id: id, name: "HRM-Dual", rssi: -55, services: [hrServiceUUID]))
        harness.events.yield(.connected(id: id))
        harness.events.yield(.servicesDiscovered(peripheralID: id, serviceUUIDs: [hrServiceUUID]))
        harness.events.yield(.characteristicsDiscovered(
            peripheralID: id, serviceUUID: hrServiceUUID, characteristicUUIDs: [hrMeasurementUUID]
        ))
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
}
