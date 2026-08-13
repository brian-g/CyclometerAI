//
//  SensorDemoData.swift
//  Cyclometer
//

import Foundation

struct NewRideDemoData {
    static let bikeName = "Road Bike Stub"
}

/// Discovered sensors for the Settings → Sensors previews. The screen is driven by
/// live BLE discovery, and previews resolve dependencies to `liveValue` unless told
/// otherwise, so previews inject these through a stub `bleCSCClient` rather than
/// seeding `State` — the stream's replay would overwrite seeded state anyway.
///
/// UUIDs are fixed so preview rows keep their identity between renders.
enum DeviceDemoData {
    static let sensors: [BLECSCClient.DiscoveredSensor] = [
        // A combo sensor holding both roles — the case that prompts for a role.
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000C5C1")!,
              name: "Wahoo RPM", roles: [.speed, .cadence], connectionState: .active,
              batteryPercent: 78,
              capabilities: .init(supportsWheelRevolutions: true, supportsCrankRevolutions: true)),
        // Never connected, so nothing has read its capabilities yet.
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000C5C2")!,
              name: "GSC-10", roles: [], connectionState: nil, batteryPercent: nil,
              capabilities: nil),
        // Unnamed peripherals must still get a row — see `discoveredIDs` in BLECSCClient.
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000C5C3")!,
              name: nil, roles: [], connectionState: nil, batteryPercent: nil,
              capabilities: nil)
    ]
}
