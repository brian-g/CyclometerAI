import SwiftUI

/// Brief, non-intrusive banner for transient ride notices — the BLE→GPS speed
/// fallback (PRD §8.4) and wheel auto-calibration (PRD §8.9). Purely presentational —
/// the owning feature's reducer is responsible for setting/clearing the text via a
/// cancellable clock-sleep effect (see `SpeedFeature.fallBackToGPS`).
struct RideBanner: View {
    let text: String
    /// Defaults to the source-switch glyph, which is what the majority of these
    /// notices are.
    var icon: String = "shuffle"

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
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

#Preview("Source switch") {
    RideBanner(text: SpeedFeature.gpsFallbackBannerText(sensorName: "Wahoo RPM"))
        .padding(.top, Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cyBgSecondary)
}

#Preview("Wheel calibration") {
    RideBanner(text: WheelCalibration.bannerText(mm: 2145), icon: "ruler")
        .padding(.top, Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cyBgSecondary)
}
