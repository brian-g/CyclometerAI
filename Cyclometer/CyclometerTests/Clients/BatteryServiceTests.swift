import ComposableArchitecture
import CoreBluetooth
import Foundation
import Testing

@testable import Cyclometer

private let batteryServiceUUID = CBUUID(string: "180F")
private let batteryLevelUUID   = CBUUID(string: "2A19")
private let otherServiceUUID   = CBUUID(string: "1816")

// MARK: - Payload parsing

@Suite("BatteryService — level parsing")
struct BatteryLevelParsingTests {

    @Test("Parses a percentage from the single-byte payload")
    func parsesPercentage() {
        #expect(BatteryService.parseLevel(from: Data([0x00])) == 0)
        #expect(BatteryService.parseLevel(from: Data([0x37])) == 55)
        #expect(BatteryService.parseLevel(from: Data([0x64])) == 100)
    }

    @Test("Empty data yields nil")
    func emptyData() {
        #expect(BatteryService.parseLevel(from: Data()) == nil)
    }

    /// 0x2A19 is defined as 0–100. A sensor answering 255 is reporting a fault, not a
    /// full charge, and "255%" on a row is worse than no battery label at all.
    @Test("Out-of-range values are rejected, not clamped")
    func outOfRangeRejected() {
        #expect(BatteryService.parseLevel(from: Data([0x65])) == nil)   // 101
        #expect(BatteryService.parseLevel(from: Data([0xFF])) == nil)   // 255
    }

    @Test("Trailing bytes are ignored")
    func trailingBytesIgnored() {
        #expect(BatteryService.parseLevel(from: Data([0x50, 0xAA, 0xBB])) == 80)
    }
}

// MARK: - Handshake

@Suite("BatteryService — discover/read handshake")
struct BatteryServiceHandshakeTests {

    /// Records every transport call the handshake makes. No peripheral is involved:
    /// the point is which operations get issued, in response to which events.
    private struct Recorder {
        let client: BLEClient
        let discoveredCharacteristics: LockIsolated<[(UUID, CBUUID, [CBUUID]?)]>
        let reads: LockIsolated<[(UUID, CBUUID, CBUUID)]>
        let notified: LockIsolated<[(Bool, UUID, CBUUID, CBUUID)]>

        init() {
            let discoveredCharacteristics = LockIsolated<[(UUID, CBUUID, [CBUUID]?)]>([])
            let reads = LockIsolated<[(UUID, CBUUID, CBUUID)]>([])
            let notified = LockIsolated<[(Bool, UUID, CBUUID, CBUUID)]>([])

            self.client = BLEClient(
                startScanning: { _ in },
                stopScanning: { _ in },
                connect: { _, _ in },
                disconnect: { _, _ in },
                discoverServices: { _, _ in },
                discoverCharacteristics: { id, service, characteristics in
                    discoveredCharacteristics.withValue { $0.append((id, service, characteristics)) }
                },
                setNotifyValue: { enabled, id, service, characteristic in
                    notified.withValue { $0.append((enabled, id, service, characteristic)) }
                },
                readValue: { id, service, characteristic in
                    reads.withValue { $0.append((id, service, characteristic)) }
                },
                events: { AsyncStream { $0.finish() } }
            )
            self.discoveredCharacteristics = discoveredCharacteristics
            self.reads = reads
            self.notified = notified
        }
    }

    @Test("A battery service in the discovery result triggers a characteristic discovery")
    func servicesDiscoveredRequestsCharacteristics() async {
        let recorder = Recorder()
        let id = UUID()

        let reading = await BatteryService.handle(
            .servicesDiscovered(peripheralID: id, serviceUUIDs: [otherServiceUUID, batteryServiceUUID]),
            bleClient: recorder.client,
            owns: { $0 == id }
        )

        #expect(reading == nil)
        #expect(recorder.discoveredCharacteristics.value.count == 1)
        #expect(recorder.discoveredCharacteristics.value[0].0 == id)
        #expect(recorder.discoveredCharacteristics.value[0].1 == batteryServiceUUID)
        #expect(recorder.discoveredCharacteristics.value[0].2 == [batteryLevelUUID])
    }

    /// Not every sensor exposes 0x180F. Nothing should be issued against one that doesn't.
    @Test("A peripheral without the battery service is left alone")
    func noBatteryServiceIsNoOp() async {
        let recorder = Recorder()
        let id = UUID()

        _ = await BatteryService.handle(
            .servicesDiscovered(peripheralID: id, serviceUUIDs: [otherServiceUUID]),
            bleClient: recorder.client,
            owns: { $0 == id }
        )

        #expect(recorder.discoveredCharacteristics.value.isEmpty)
    }

    /// Read *and* subscribe: the read guarantees a value on sensors that don't notify,
    /// the subscription keeps it live on the ones that do.
    @Test("Discovering the level characteristic issues both a read and a notify subscription")
    func characteristicsDiscoveredReadsAndSubscribes() async {
        let recorder = Recorder()
        let id = UUID()

        let reading = await BatteryService.handle(
            .characteristicsDiscovered(
                peripheralID: id, serviceUUID: batteryServiceUUID,
                characteristicUUIDs: [batteryLevelUUID]
            ),
            bleClient: recorder.client,
            owns: { $0 == id }
        )

        #expect(reading == nil)
        #expect(recorder.reads.value.count == 1)
        #expect(recorder.reads.value[0].0 == id)
        #expect(recorder.reads.value[0].1 == batteryServiceUUID)
        #expect(recorder.reads.value[0].2 == batteryLevelUUID)
        #expect(recorder.notified.value.count == 1)
        #expect(recorder.notified.value[0].0 == true)
        #expect(recorder.notified.value[0].3 == batteryLevelUUID)
    }

    /// Characteristics for another service arrive on the same event; the handshake must
    /// not read 0x2A19 off a service that isn't the battery service.
    @Test("Characteristics of another service are ignored")
    func otherServiceCharacteristicsIgnored() async {
        let recorder = Recorder()
        let id = UUID()

        _ = await BatteryService.handle(
            .characteristicsDiscovered(
                peripheralID: id, serviceUUID: otherServiceUUID,
                characteristicUUIDs: [batteryLevelUUID]
            ),
            bleClient: recorder.client,
            owns: { $0 == id }
        )

        #expect(recorder.reads.value.isEmpty)
        #expect(recorder.notified.value.isEmpty)
    }

    @Test("A level value update surfaces the parsed percentage")
    func valueUpdateSurfacesLevel() async {
        let recorder = Recorder()
        let id = UUID()

        let reading = await BatteryService.handle(
            .characteristicValueUpdated(
                peripheralID: id, characteristicUUID: batteryLevelUUID, value: Data([0x4B])
            ),
            bleClient: recorder.client,
            owns: { $0 == id }
        )

        #expect(reading?.peripheralID == id)
        #expect(reading?.level == 75)
    }

    @Test("A malformed level value surfaces nothing")
    func malformedValueSurfacesNothing() async {
        let recorder = Recorder()
        let id = UUID()

        let reading = await BatteryService.handle(
            .characteristicValueUpdated(
                peripheralID: id, characteristicUUID: batteryLevelUUID, value: Data([0xFF])
            ),
            bleClient: recorder.client,
            owns: { $0 == id }
        )

        #expect(reading == nil)
    }

    /// The transport broadcasts every peripheral's events to every client, so `owns` is
    /// the only thing keeping one sensor client from reading another's battery.
    @Test("Events for peripherals the caller doesn't own are ignored throughout")
    func unownedPeripheralIgnored() async {
        let recorder = Recorder()
        let mine = UUID()
        let theirs = UUID()

        _ = await BatteryService.handle(
            .servicesDiscovered(peripheralID: theirs, serviceUUIDs: [batteryServiceUUID]),
            bleClient: recorder.client, owns: { $0 == mine }
        )
        _ = await BatteryService.handle(
            .characteristicsDiscovered(
                peripheralID: theirs, serviceUUID: batteryServiceUUID,
                characteristicUUIDs: [batteryLevelUUID]
            ),
            bleClient: recorder.client, owns: { $0 == mine }
        )
        let reading = await BatteryService.handle(
            .characteristicValueUpdated(
                peripheralID: theirs, characteristicUUID: batteryLevelUUID, value: Data([0x50])
            ),
            bleClient: recorder.client, owns: { $0 == mine }
        )

        #expect(recorder.discoveredCharacteristics.value.isEmpty)
        #expect(recorder.reads.value.isEmpty)
        #expect(recorder.notified.value.isEmpty)
        #expect(reading == nil)
    }
}
