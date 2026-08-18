//
//  SensorDemoData.swift
//  Cyclometer
//

import Foundation

struct NewRideDemoData {
    static let bikeName = "Road Bike Stub"
}

/// Discovered devices for the Settings → Sensors previews. The screen is driven by
/// live BLE discovery, and previews resolve dependencies to `liveValue` unless told
/// otherwise, so previews inject these through stub clients rather than seeding
/// `State` — the streams' replay would overwrite seeded state anyway.
///
/// Split by kind because that is how the screen receives them: one stream per client,
/// merged on read (#98).
///
/// UUIDs are fixed so preview rows keep their identity between renders.
enum DeviceDemoData {
    static let cscSensors: [DiscoveredDevice] = [
        // A combo sensor holding both roles — the case that prompts for a role.
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000C5C1")!,
              name: "Wahoo RPM", kinds: [.speedCadence], roles: [.speed, .cadence],
              connectionState: .active, batteryPercent: 78,
              capabilities: .init(supportsWheelRevolutions: true, supportsCrankRevolutions: true)),
        // Never connected, so nothing has read its capabilities yet.
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000C5C2")!,
              name: "GSC-10", kinds: [.speedCadence]),
        // Unnamed peripherals must still get a row — see `discoveredIDs` in BLECSCClient.
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000C5C3")!,
              name: nil, kinds: [.speedCadence])
    ]

    static let radarDevices: [DiscoveredDevice] = [
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000DA01")!,
              name: "Varia RTL515", kinds: [.radar])
    ]

    static let hrDevices: [DiscoveredDevice] = [
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!,
              name: "Polar H10", kinds: [.heartRate])
    ]
}
