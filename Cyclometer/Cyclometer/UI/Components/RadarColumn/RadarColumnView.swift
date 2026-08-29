import SwiftUI

/// 24pt fixed-width radar column — full-height lane on the right edge of the
/// active ride dashboard (S06), reused as-is from before #137 aside from the
/// added `isOffline` state.
///
/// Layout (per S06 layer data):
///   • Background: full-height, colour-coded by dominant threat level
///   • Vehicle glyphs: 16pt wide, positioned top → bottom by proximity
///     - Top    = critical / closest threat   (L3)
///     - Middle = warning / approaching       (L2)
///     - Bottom = car / distant               (L0)
///
/// Visibility:
///   • Instantiated only when `ActiveRideFeature.State.isRadarSidebarVisible` is
///     true (caller: the `HStack` lane in `RideDashboardView.gridPage`, sitting
///     beside — not inside — the widget `Grid`, so it spans the full dashboard
///     height rather than a single grid row)
///   • Not instantiated at all when radar has never been paired this ride — the
///     caller reclaims the full width with no reflow
///
/// Target hardware: Garmin Varia RTL515 / RCT715 (up to 8 targets, range 0–140 m)
struct RadarColumnView: View {
    let targets: [RadarTarget]
    /// True once a previously-paired radar loses connection (mid-ride disconnect
    /// or the 10s reconnect grace window) — `targets` may be stale at that point
    /// and must not be rendered (#137).
    let isOffline: Bool

    // Dominant threat drives background colour
    private var dominantThreat: RadarTarget.ThreatLevel {
        if targets.contains(where: { $0.threatLevel == .danger })  { return .danger }
        if targets.contains(where: { $0.threatLevel == .warning }) { return .warning }
        return .allClear
    }

    private var columnBackground: Color {
        switch dominantThreat {
        case .allClear: return Color.cyBgSecondary
        case .warning:  return Color.cyRatingOkayBg
        case .danger:   return Color.cyRatingBadBg
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                if isOffline {
                    Color.cyBgTertiary
                } else {
                    // Background fill
                    columnBackground
                        .animation(.easeInOut(duration: 0.2), value: dominantThreat)

                    // Vehicle glyphs — sorted by range ascending so closest is at top.
                    // Each glyph is 16×16pt, centred in the 24pt column.
                    // Y position maps range (0–140 m) linearly to column height.
                    let sorted = targets.sorted { $0.rangeMetres < $1.rangeMetres }
                    ForEach(sorted) { target in
                        VehicleGlyphView(threatLevel: target.threatLevel)
                            .frame(width: Spacing.lg, height: Spacing.lg)
                            .position(
                                x: Spacing.xl / 2,   // centre of radar column
                                y: yPosition(for: target.rangeMetres, in: geo.size.height)
                            )
                            // Radar updates arrive as discrete BLE notifications, not a
                            // continuous stream — without this, each update snaps the
                            // glyph straight to its new Y instead of interpolating there.
                            // Linear, not eased: a vehicle closes at a roughly constant
                            // rate between updates, so it should track at a constant
                            // screen speed too, not decelerate into each new position.
                            .animation(.linear(duration: 0.2), value: target.rangeMetres)
                    }
                }
            }
            // S06: a 1pt inside border on the left edge only, separating the
            // strip from the widget grid — confirmed against Design.sketch's
            // `background` layer style, not a guess.
            .overlay(alignment: .leading) {
                Color.cyBorderStrong.frame(width: 1)
            }
        }
    }

    /// Maps vehicle range (0–140 m) to a Y position within the column.
    /// Closest vehicle (0 m) → top; furthest (140 m) → bottom.
    private func yPosition(for rangeMetres: Double, in height: CGFloat) -> CGFloat {
        let maxRange: Double = 140
        let fraction = min(rangeMetres / maxRange, 1.0)
        // Reserve half-glyph padding top and bottom so glyphs don't clip at edges
        let usable = Double(height) - Double(Spacing.xl)
        return CGFloat(Double(Spacing.xl / 2) + fraction * usable)
    }
}

// MARK: - Vehicle Glyph

/// Single vehicle indicator — shape and colour encode threat level.
private struct VehicleGlyphView: View {
    let threatLevel: RadarTarget.ThreatLevel

    private var glyphColor: Color {
        switch threatLevel {
        case .allClear: return .cyRatingGood
        case .warning:  return .cyRatingOkay
        case .danger:   return .cyRatingBad
        }
    }

    var body: some View {
        Image(systemName: "car.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(glyphColor)
            .animation(.easeInOut(duration: 0.15), value: threatLevel)
    }
}

// MARK: - Previews

// Full dashboard height (S06 Sketch measurement), not a single grid row —
// matches how RideDashboardView actually sizes this lane.
private let previewHeight: CGFloat = 675

#Preview("Clear — No Vehicles") {
    RadarColumnView(targets: [], isOffline: false)
        .frame(width: Spacing.radarColumnWidth, height: previewHeight)
}

#Preview("Mixed Threats") {
    RadarColumnView(
        targets: [
            RadarTarget(
                id: VariaRadarClient.vehicleSlotIDs[0],
                relativeVelocityMPS: 2,
                rangeMetres: 120,
                threatLevel: .allClear
            ),
            RadarTarget(
                id: VariaRadarClient.vehicleSlotIDs[1],
                relativeVelocityMPS: 6,
                rangeMetres: 65,
                threatLevel: .warning
            ),
            RadarTarget(
                id: VariaRadarClient.vehicleSlotIDs[2],
                relativeVelocityMPS: 9,
                rangeMetres: 15,
                threatLevel: .danger
            ),
        ],
        isOffline: false
    )
    .frame(width: Spacing.radarColumnWidth, height: previewHeight)
}

#Preview("Eight Vehicles") {
    RadarColumnView(
        targets: VariaRadarClient.vehicleSlotIDs.enumerated().map { index, id in
            RadarTarget(
                id: id,
                relativeVelocityMPS: 4,
                rangeMetres: Double(10 + index * 17),
                threatLevel: index < 2 ? .danger : index < 5 ? .warning : .allClear
            )
        },
        isOffline: false
    )
    .frame(width: Spacing.radarColumnWidth, height: previewHeight)
}

#Preview("Offline") {
    // Stale targets from before the disconnect — must be ignored while offline.
    RadarColumnView(
        targets: [
            RadarTarget(
                id: VariaRadarClient.vehicleSlotIDs[0],
                relativeVelocityMPS: 9,
                rangeMetres: 15,
                threatLevel: .danger
            )
        ],
        isOffline: true
    )
    .frame(width: Spacing.radarColumnWidth, height: previewHeight)
}
