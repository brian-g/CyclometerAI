import SwiftUI

/// Brief, non-intrusive banner for ride notices — the BLE→GPS speed fallback (PRD §8.4),
/// wheel auto-calibration (PRD §8.9), and turns and off-route (PRD §8.6, #197). Purely
/// presentational — the owning feature's reducer sets and clears it: a cancellable
/// clock-sleep effect for the transient ones (see `SpeedFeature.fallBackToGPS`), rejoining
/// the route for off-route.
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

#Preview("Turn") {
    RideBanner(
        text: NavigationFeature.bannerText(for: Maneuver(
            coordinate: RouteCoordinate(latitude: 0, longitude: 0, elevationMeters: nil),
            direction: .left,
            name: "Turn left onto County Road S",
            distanceAlongRouteMeters: 0
        )),
        icon: "arrow.turn.up.left"
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
