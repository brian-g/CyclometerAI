import SwiftUI

/// Reusable secondary metric tile — used in the two-column grid on the Ride Metrics page.
/// HR tile uses the zone colour as its border treatment.
struct MetricTileView: View {
    let label: String
    let value: String
    let unit: String
    var borderColor: Color = Color.cyBorderSubtle

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.cyCaption)
                .foregroundStyle(Color.cyTextSecondary)
                .textCase(.uppercase)
                .tracking(1.5)

            HStack(alignment: .lastTextBaseline, spacing: 3) {
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cyBgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(borderColor, lineWidth: 1.5)
        )
    }
}
