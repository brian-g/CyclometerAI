import Foundation
import Testing
import ComposableArchitecture
@testable import Cyclometer

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
}
