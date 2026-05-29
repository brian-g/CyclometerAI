import SwiftUI

/// 24pt fixed-width radar column — right edge of the Ride Metrics dashboard (S06).
///
/// Layout (per S06 layer data):
///   • Background: full-height, colour-coded by dominant threat level
///   • Vehicle glyphs: 16pt wide, positioned top → bottom by proximity
///     - Top    = critical / closest threat   (L3)
///     - Middle = warning / approaching       (L2)
///     - Bottom = car / distant               (L0)
///
/// Visibility:
///   • Rendered only when a Varia device is paired (caller gates via `if store.isRadarPaired`)
///   • Zero-width when unpaired — the HStack in RideMetricsView collapses it with no reflow
///
/// Target hardware: Garmin Varia RTL515 / RCT715 (up to 8 targets, range 0–140 m)
struct RadarColumnView: View {
    let targets: [RadarTarget]

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
                // Background fill
                columnBackground
                    .animation(.easeInOut(duration: 0.2), value: dominantThreat)

                // Vehicle glyphs — sorted by range ascending so closest is at top.
                // Each glyph is 16×16pt, centred in the 24pt column.
                // Y position maps range (0–140 m) linearly to column height.
                let sorted = targets.sorted { $0.rangeMetres < $1.rangeMetres }
                ForEach(sorted) { target in
                    VehicleGlyphView(threatLevel: target.threatLevel)
                        .frame(width: 16, height: 16)
                        .position(
                            x: 12,   // centre of 24pt column
                            y: yPosition(for: target.rangeMetres, in: geo.size.height)
                        )
                }
            }
        }
    }

    /// Maps vehicle range (0–140 m) to a Y position within the column.
    /// Closest vehicle (0 m) → top; furthest (140 m) → bottom.
    private func yPosition(for rangeMetres: Double, in height: CGFloat) -> CGFloat {
        let maxRange: Double = 140
        let fraction = min(rangeMetres / maxRange, 1.0)
        // Reserve 12pt padding top and bottom so glyphs don't clip at edges
        let usable = Double(height) - 24
        return CGFloat(12 + fraction * usable)
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
