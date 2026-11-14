import SwiftUI

/// Brief, non-intrusive banner for ride notices — the BLE→GPS speed fallback (PRD §8.4),
/// wheel auto-calibration (PRD §8.9), rain on the route ahead (#152), and off-route (PRD §8.6,
/// #197); a turn has the centred `TurnInstructionOverlay` instead. Purely
/// presentational — the owning feature's reducer sets and clears it: a cancellable
/// clock-sleep effect for the transient ones (see `SpeedFeature.fallBackToGPS`), rejoining
/// the route for off-route.
struct RideBanner: View {
    let text: String
    /// Defaults to the source-switch glyph, which is what the majority of these
    /// notices are.
    var icon: String = "shuffle"
    /// What VoiceOver reads in place of `text`, for a notice whose text carries unit symbols
    /// (#568). Nil reads `text` as written.
    var spokenText: String?

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .foregroundStyle(Color.cyInfo)
            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.cyTextPrimary)
                .accessibilityLabel(spokenText ?? text)
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

#Preview("Rain ahead") {
    let rain = RainAhead(
        chance: 0.7, condition: .rain, isDaylight: true, distanceAheadMeters: 18_400, arrival: .now
    )
    RideBanner(
        text: rain.bannerText(unitSystem: .metric),
        icon: rain.symbolName,
        spokenText: rain.spokenText(unitSystem: .metric)
    )
        .padding(.top, Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cyBgSecondary)
}

#Preview("Rain here") {
    let rain = RainAhead(
        chance: 0.6, condition: .rain, isDaylight: true, distanceAheadMeters: 0, arrival: .now
    )
    RideBanner(
        text: rain.bannerText(unitSystem: .metric),
        icon: rain.symbolName,
        spokenText: rain.spokenText(unitSystem: .metric)
    )
        .padding(.top, Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cyBgSecondary)
}

#Preview("Off route") {
    RideBanner(text: NavigationFeature.offRouteBannerText, icon: "exclamationmark.triangle")
        .padding(.top, Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cyBgSecondary)
}
