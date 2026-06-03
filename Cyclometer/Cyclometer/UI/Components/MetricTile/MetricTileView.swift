import SwiftUI

/// Reusable secondary metric tile — used in the two-column grid on the Ride Metrics page.
/// HR tile uses the zone colour as its border treatment.
struct MetricTileView: View {
    let label: String
    let value: String
    let unit: String
    var borderColor: Color = Color.cyBorderSubtle

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(label)
                .font(.cyCaption)
                .foregroundStyle(Color.cyTextSecondary)
                .textCase(.uppercase)
                .tracking(1.5)

            HStack(alignment: .lastTextBaseline, spacing: Spacing.xs) {
                Text(value)
                    .font(.cyMetricMedium)
                    .foregroundStyle(Color.cyTextPrimary)
                    .monospacedDigit()
                if !unit.isEmpty {
                    Text(unit)
                        .font(.cyCaption)
                        .foregroundStyle(Color.cyTextSecondary)
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cyBgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerMd))
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.cornerMd)
                .strokeBorder(borderColor, lineWidth: Spacing.strokeThin)
        )
    }
}
