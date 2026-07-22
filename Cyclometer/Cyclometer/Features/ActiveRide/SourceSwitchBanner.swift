import SwiftUI

/// Brief, non-intrusive banner for source-switch notifications (e.g. BLE→GPS
/// speed fallback). Purely presentational — the owning feature's reducer is
/// responsible for setting/clearing the text via a cancellable clock-sleep
/// effect (see SpeedFeature.fallBackToGPS).
struct SourceSwitchBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "shuffle")
                .foregroundStyle(Color.cyInfo)
            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.cyTextPrimary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color.cyBgElevated, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.cyBorder, lineWidth: Spacing.strokeThin))
        .padding(.horizontal, Spacing.lg)
    }
}

// MARK: - Previews

#Preview("Banner") {
    SourceSwitchBanner(text: SpeedFeature.gpsFallbackBannerText(sensorName: "Wahoo RPM"))
        .padding(.top, Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cyBgSecondary)
}
