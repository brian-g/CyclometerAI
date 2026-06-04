import SwiftUI

/// Compact heart-rate zone badge — "Z4" with zone colour.
struct HRZoneBadgeView: View {
    let zone: Int   // 1–5

    var body: some View {
        Text("Z\(zone)")
            .font(.system(size: 11, weight: .black, design: .monospaced))
            .foregroundStyle(Color.hrZone(zone))
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(Color.hrZone(zone).opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerSm))
    }
}
