import SwiftUI

/// Battery level for a connected sensor, as a glyph plus percentage. Shared by the
/// Start sheet's Sensors group (S05.1) and the Sensors settings screen (S11), which
/// both sit in the trailing slot of `SensorListRowView`.
///
/// Deciding *whether* to show battery stays with the caller — each list has its own
/// rule about what counts as connected. This only draws a level it has been given.
struct SensorBatteryLabel: View {
    let percent: Int

    /// At or below this the label turns `cyRatingBad`: the rider should charge the
    /// sensor before setting off rather than lose it mid-ride.
    private static let lowThreshold = 20

    /// Upper bound of each glyph's band. The system draws five discrete fill levels,
    /// so the bands are centred on them — 50% reads as half full, not as three
    /// quarters.
    private static let glyphBands: [(upperBound: Int, symbol: String)] = [
        (13, "battery.0percent"),
        (38, "battery.25percent"),
        (63, "battery.50percent"),
        (88, "battery.75percent"),
    ]

    var body: some View {
        Label("\(percent)%", systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .font(.caption)
            .labelIconToTitleSpacing(Spacing.xs)
            .foregroundStyle(isLow ? Color.cyRatingBad : Color.secondary)
            .accessibilityLabel(isLow ? "Battery \(percent) percent, low" : "Battery \(percent) percent")
    }

    private var isLow: Bool { percent <= Self.lowThreshold }

    private var symbol: String {
        Self.glyphBands.first { percent < $0.upperBound }?.symbol ?? "battery.100percent"
    }
}

// MARK: - Previews

#Preview("Battery levels") {
    VStack(alignment: .trailing, spacing: Spacing.md) {
        SensorBatteryLabel(percent: 100)
        SensorBatteryLabel(percent: 78)
        SensorBatteryLabel(percent: 50)
        SensorBatteryLabel(percent: 30)
        SensorBatteryLabel(percent: 12)
        SensorBatteryLabel(percent: 0)
    }
    .padding()
}
