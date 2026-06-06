import Testing
import ComposableArchitecture
import CoreBluetooth
@testable import Cyclometer

@Suite("BLEClient — test value")
struct BLEClientTests {

    @Test("Test value startScanning does not crash")
    func startScanningNoOp() async {
        let client = BLEClient.testValue
        await client.startScanning([CBUUID(string: "180D")])
    }

    @Test("Test value stopScanning does not crash")
    func stopScanningNoOp() async {
        let client = BLEClient.testValue
        await client.stopScanning()
    }

    @Test("Test value connect does not crash")
    func connectNoOp() async {
        let client = BLEClient.testValue
        await client.connect(UUID())
    }

    @Test("Test value disconnect does not crash")
    func disconnectNoOp() async {
        let client = BLEClient.testValue
        await client.disconnect(UUID())
    }

    @Test("Test value discoverServices does not crash")
    func discoverServicesNoOp() async {
        let client = BLEClient.testValue
        await client.discoverServices(UUID(), nil)
    }

    @Test("Test value discoverCharacteristics does not crash")
    func discoverCharacteristicsNoOp() async {
        let client = BLEClient.testValue
        await client.discoverCharacteristics(UUID(), CBUUID(string: "180D"), nil)
    }

    @Test("Test value setNotifyValue does not crash")
    func setNotifyValueNoOp() async {
        let client = BLEClient.testValue
        await client.setNotifyValue(true, UUID(), CBUUID(string: "180D"), CBUUID(string: "2A37"))
    }

    @Test("Test value events stream completes immediately")
    func eventsStreamCompletes() async {
        let client = BLEClient.testValue
        var count = 0
        for await _ in client.events() {
            count += 1
        }
        #expect(count == 0)
    }

    @Test("Controllable events stream delivers injected events")
    func controllableStream() async {
        let peripheralID = UUID()
        let (stream, continuation) = AsyncStream<BLEEvent>.makeStream()

        let client = BLEClient(
            startScanning: { _ in },
            stopScanning: { },
            connect: { _ in },
            disconnect: { _ in },
            discoverServices: { _, _ in },
            discoverCharacteristics: { _, _, _ in },
            setNotifyValue: { _, _, _, _ in },
            events: { stream }
        )

        Task {
            continuation.yield(.stateChanged(.poweredOn))
            continuation.yield(.discovered(id: peripheralID, name: "Varia RTL515", rssi: -65))
            continuation.yield(.connected(id: peripheralID))
            continuation.finish()
        }

        var received: [BLEEvent] = []
        for await event in client.events() {
            received.append(event)
        }

        #expect(received.count == 3)

        guard case .stateChanged(.poweredOn) = received[0] else {
            Issue.record("Expected stateChanged(.poweredOn), got \(received[0])")
            return
        }
        guard case .discovered(let id, let name, _) = received[1] else {
            Issue.record("Expected .discovered, got \(received[1])")
            return
        }
        #expect(id == peripheralID)
        #expect(name == "Varia RTL515")

        guard case .connected(let connectedID) = received[2] else {
            Issue.record("Expected .connected, got \(received[2])")
            return
        }
        #expect(connectedID == peripheralID)
    }

    @Test("Characteristic value event carries correct data")
    func characteristicValueEvent() async {
        let peripheralID = UUID()
        let charUUID = CBUUID(string: "6A4E3202-667B-11E3-949A-0800200C9A66")
        let payload = Data([0x03, 0x01, 0x05, 0x28])

        let (stream, continuation) = AsyncStream<BLEEvent>.makeStream()
        let client = BLEClient(
            startScanning: { _ in },
            stopScanning: { },
            connect: { _ in },
            disconnect: { _ in },
            discoverServices: { _, _ in },
            discoverCharacteristics: { _, _, _ in },
            setNotifyValue: { _, _, _, _ in },
            events: { stream }
        )

        Task {
            continuation.yield(.characteristicValueUpdated(
                peripheralID: peripheralID,
                characteristicUUID: charUUID,
                value: payload
            ))
            continuation.finish()
        }

        var received: [BLEEvent] = []
        for await event in client.events() {
            received.append(event)
        }

        guard case .characteristicValueUpdated(let pid, let uuid, let value) = received.first else {
            Issue.record("Expected .characteristicValueUpdated")
            return
        }
        #expect(pid == peripheralID)
        #expect(uuid == charUUID)
        #expect(value == payload)
    }

    @Test("Bluetooth permission denied — no crash on scan attempt")
    func permissionDeniedNoCrash() async {
        // In testValue, scanning with no CBCentralManager present never throws.
        let client = BLEClient.testValue
        await client.startScanning([CBUUID(string: "6A4E3200-667B-11E3-949A-0800200C9A66")])
        await client.connect(UUID())
        await client.stopScanning()
    }
}
