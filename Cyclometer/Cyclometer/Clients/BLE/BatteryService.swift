@preconcurrency import CoreBluetooth
import Foundation
import os

private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "ble")

// MARK: - BatteryService

/// Bluetooth SIG Battery Service (0x180F) — shared by every sensor client.
///
/// Battery level is a property of the *device*, not of the sensor profile it serves,
/// so the radar, HR and CSC clients all run the identical discover → read handshake.
/// It lives here once rather than three times.
enum BatteryService {
    static let serviceUUID = CBUUID(string: "180F")
    static let levelUUID   = CBUUID(string: "2A19")

    /// Parse a Battery Level (0x2A19) value: a single byte, 0–100 percent.
    ///
    /// Out-of-range values are rejected rather than clamped — a sensor reporting 255
    /// is not at full charge, it is not reporting, and a bogus "255%" on screen is
    /// worse than no battery label at all.
    static func parseLevel(from data: Data) -> Int? {
        guard let byte = data.first, byte <= 100 else { return nil }
        return Int(byte)
    }

    /// Advance the battery handshake for peripherals the caller owns, and surface a
    /// level when one arrives. Returns `nil` for every event that isn't a battery
    /// reading, which is nearly all of them.
    ///
    /// Call once at the top of a sensor client's event loop, before its own `switch`.
    /// The events consumed here are disjoint from the profile flows — the only overlap
    /// is `.characteristicValueUpdated`, and this claims it only for 0x2A19.
    ///
    /// Two contracts the caller must honour:
    /// - include ``serviceUUID`` in the `discoverServices` call it makes on `.connected`.
    ///   A separate call would work, but `didDiscoverServices` broadcasts the peripheral's
    ///   *full* service list, so it would re-fire the caller's own discover → notify chain.
    /// - clear its cached level on `.disconnected`. There is no event for "battery
    ///   unknown again", and a failed read produces no event at all.
    ///
    /// Both a one-shot read and a notify subscription are issued: most sensors push
    /// battery on change, and those that don't ignore the subscription, leaving the
    /// connect-time reading to stand.
    static func handle(
        _ event: BLEEvent,
        bleClient: BLEClient,
        owns: @Sendable (UUID) -> Bool
    ) async -> (peripheralID: UUID, level: Int)? {
        switch event {
        case .servicesDiscovered(let id, let serviceUUIDs):
            guard owns(id), serviceUUIDs.contains(serviceUUID) else { return nil }
            await bleClient.discoverCharacteristics(id, serviceUUID, [levelUUID])

        case .characteristicsDiscovered(let id, let service, let characteristicUUIDs):
            guard owns(id), service == serviceUUID,
                  characteristicUUIDs.contains(levelUUID) else { return nil }
            await bleClient.readValue(id, serviceUUID, levelUUID)
            await bleClient.setNotifyValue(true, id, serviceUUID, levelUUID)

        case .characteristicValueUpdated(let id, let characteristic, let value):
            guard owns(id), characteristic == levelUUID else { return nil }
            guard let level = parseLevel(from: value) else {
                let hex = value.map { String(format: "%02X", $0) }.joined(separator: " ")
                logger.notice("battery value [\(hex, privacy: .public)] → out of range, ignored")
                return nil
            }
            logger.notice("battery \(level)% on \(id, privacy: .public)")
            return (id, level)

        default:
            break
        }
        return nil
    }
}
