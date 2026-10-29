import SwiftUI

/// The ride's Sensors sheet (#466), opened by the toolbar's Sensors button (#464 opens the same
/// one): every paired device with its live status and, while connected, its battery.
///
/// Status only. Pairing and forgetting stay on S11, and reconnecting is the clients' own.
///
/// `devices` is called in this view's own `body`, not the presenter's `.sheet` builder, so the
/// open sheet follows sensors as they connect and drop (see `RideMetricsSheet`, #144).
struct SensorsSheet: View {
    var devices: () -> [SensorHealthFeature.Device]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let devices = devices()
        NavigationStack {
            SensorsList(devices: devices)
                .navigationTitle("Sensors")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .close) { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}

/// The sheet's rows, apart from its navigation chrome so a snapshot can pin them.
struct SensorsList: View {
    let devices: [SensorHealthFeature.Device]

    var body: some View {
        List {
            // One row per device, drawn as S10 and S11 draw one, so a combo reads the same everywhere.
            ForEach(devices) { device in
                let style = SensorRowStyle.device(roles: Set(device.roles), kinds: [])
                SensorListRowView(
                    icon: style.symbol,
                    iconTint: style.tint,
                    title: device.title,
                    subtitle: device.name
                ) {
                    VStack(alignment: .trailing) {
                        SensorStatusBadge(status: device.isConnected ? .connected : .searching)
                        if device.isConnected, let battery = device.batteryPercent {
                            SensorBatteryLabel(percent: battery)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Missing and low") {
    SensorsList(devices: [.sampleRadarLow, .sampleHeartRateHealthy, .sampleComboMissing])
}

#Preview("All connected, dark") {
    SensorsList(devices: [.sampleRadarLow, .sampleHeartRateHealthy])
        .preferredColorScheme(.dark)
}

#Preview("Sheet") {
    Color.cyBgSecondary
        .sheet(isPresented: .constant(true)) {
            SensorsSheet { [.sampleRadarMissing, .sampleHeartRateLow, .sampleComboMissing] }
        }
}
