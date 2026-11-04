import SwiftUI

/// The ride toolbar's Sensors button (#464, #466): shown while a paired sensor is missing or its
/// battery is low, with a badge counting those devices. Opens the Sensors sheet.
///
/// Quiet by design: it appears, nothing more. No sound, haptic or banner, which would compete
/// with radar alerts (UX.md §S10 "Sensors"). Sketch frame "Sxx - Route overlay", group
/// "sensor button".
struct SensorsButton: View {
    /// The devices needing attention; the caller hides the button when there are none.
    let devices: [SensorHealthFeature.Device]
    let action: () -> Void

    var body: some View {
        RideControlButton("Sensors", systemImage: "antenna.radiowaves.left.and.right", action: action)
            .overlay(alignment: .topTrailing) {
                // A tap on the badge, the part a rider's eye goes to, must still reach the button.
                badge.accessibilityHidden(true).allowsHitTesting(false)
            }
            .accessibilityLabel(Self.accessibilityLabel(for: devices))
            .accessibilityHint("Opens sensor status")
    }

    /// The count in `cyRatingBad`, as the frame draws it. `cyTextOnPrimary` over it is white in
    /// light mode and black in dark, where `ratingBad` lightens: AA contrast in both.
    private var badge: some View {
        Text(devices.count, format: .number)
            .font(.caption2.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(Color.cyTextOnPrimary)
            .padding(.horizontal, Spacing.xs)
            .frame(minWidth: Spacing.toolbarBadge, minHeight: Spacing.toolbarBadge)
            .background(Color.cyRatingBad, in: Capsule())
            .offset(y: -Spacing.xs)
    }

    /// "Sensors, 1 not found", "Sensors, low battery: Radar, 18 percent", or both joined.
    static func accessibilityLabel(for devices: [SensorHealthFeature.Device]) -> String {
        var parts = ["Sensors"]
        let missing = devices.filter(\.isMissing).count
        if missing > 0 {
            parts.append("\(missing) not found")
        }
        let low = devices.filter(\.isBatteryLow).compactMap { device in
            device.batteryPercent.map { "\(device.title), \($0) percent" }
        }
        if !low.isEmpty {
            parts.append("low battery: " + low.joined(separator: ", "))
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Previews

extension SensorHealthFeature.Device {
    private static let radarID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let comboID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private static let heartRateID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    static let sampleRadarMissing = Self(id: radarID, roles: [.radar], name: "Varia RTL515",
                                         isConnected: false, batteryPercent: nil)
    static let sampleComboMissing = Self(id: comboID, roles: [.speed, .cadence], name: "Wahoo RPM",
                                         isConnected: false, batteryPercent: nil)
    static let sampleRadarLow = Self(id: radarID, roles: [.radar], name: "Varia RTL515",
                                     isConnected: true, batteryPercent: 18)
    static let sampleHeartRateLow = Self(id: heartRateID, roles: [.heartRate], name: "HRM-Pro",
                                         isConnected: true, batteryPercent: 9)
    static let sampleHeartRateHealthy = Self(id: heartRateID, roles: [.heartRate], name: "HRM-Pro",
                                             isConnected: true, batteryPercent: 82)
}

#Preview("One missing") {
    SensorsButton(devices: [.sampleRadarMissing]) {}
        .padding()
}

#Preview("Two missing") {
    SensorsButton(devices: [.sampleRadarMissing, .sampleComboMissing]) {}
        .padding()
}

#Preview("One low") {
    SensorsButton(devices: [.sampleRadarLow]) {}
        .padding()
}

#Preview("Two low") {
    SensorsButton(devices: [.sampleRadarLow, .sampleHeartRateLow]) {}
        .padding()
}

#Preview("Missing and low, dark") {
    SensorsButton(devices: [.sampleComboMissing, .sampleHeartRateLow]) {}
        .padding()
        .preferredColorScheme(.dark)
}
