import Foundation

/// Decoded CSC Feature (0x2A5C) payload — what the sensor is physically able to
/// report, and therefore which roles it can fill (BLE.md §5.0).
///
/// Authoritative and available as soon as the characteristic is read, unlike the
/// measurement-flags inference it supersedes, which cannot answer until the rider
/// starts moving. The flags path survives as a fallback for sensors that don't
/// answer the read — see `BLECSCClient.narrowCapabilitiesLocked`.
///
/// Lived inside `BLECSCClient` until #98, when `DiscoveredDevice` — a `Models/` type —
/// started carrying it. `BLECSCClient.Capabilities` remains as a typealias, so nothing
/// that already spelled it that way had to change.
struct CSCCapabilities: Equatable, Sendable {
    var supportsWheelRevolutions: Bool   // bit 0 — can fill the Speed role
    var supportsCrankRevolutions: Bool   // bit 1 — can fill the Cadence role

    init(supportsWheelRevolutions: Bool, supportsCrankRevolutions: Bool) {
        self.supportsWheelRevolutions = supportsWheelRevolutions
        self.supportsCrankRevolutions = supportsCrankRevolutions
    }

    /// Returns nil for malformed payloads. Failable rather than defaulting an
    /// empty payload to "supports nothing" (as BLE.md §7's sketch did): a frame
    /// too short to read is a broken frame, and treating it as a real answer
    /// would strip both roles off a working sensor.
    init?(featureData: Data) {
        // Spec'd as 16-bit little-endian. Only the low byte carries bits 0–1, but
        // read the field as declared rather than assuming a one-byte payload.
        let bytes = [UInt8](featureData)
        guard let low = bytes.first else { return nil }
        let flags = UInt16(low) | (bytes.count > 1 ? UInt16(bytes[1]) << 8 : 0)
        supportsWheelRevolutions = flags & 0x0001 != 0
        supportsCrankRevolutions = flags & 0x0002 != 0
    }

    /// The roles this sensor could fill.
    var supportedRoles: Set<SensorRole> {
        var roles: Set<SensorRole> = []
        if supportsWheelRevolutions { roles.insert(.speed) }
        if supportsCrankRevolutions { roles.insert(.cadence) }
        return roles
    }

    /// Only a sensor that can do both leaves the rider a decision to make; a
    /// single-capability sensor is auto-assigned with no prompt (BLE.md §5.0).
    var requiresRoleSelection: Bool { supportsWheelRevolutions && supportsCrankRevolutions }
}
