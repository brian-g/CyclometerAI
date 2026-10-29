import SwiftUI

// MARK: - W23 Active Calories Widget

/// W23 — Active Calories 1×1 (#465): the ride's active energy so far, in kcal. The estimate is
/// `RideEnergy.activeKilocalories`, recomputed once a minute over the track, so the ride ends on the
/// value written to its Health workout. Tapping opens the Calories sheet.
///
/// Always on the dashboard: with no body mass in Health, or before the first minute's estimate, it
/// reads "—".
struct CaloriesWidget: View {
    let kilocalories: Double?
    let rider: EnergyRiderStatus
    /// The Calories sheet's data. A closure so the card never reads it; only the open sheet does,
    /// in its own body (#144).
    var metrics: () -> CaloriesMetrics = { CaloriesMetrics() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel("Active Calories")
            if let kilocalories {
                HeroNumber(kilocalories, decimals: 0, unit: "kcal").heroNumberSize(.medium)
            } else {
                HeroNumber("—", unit: "").heroNumberSize(.medium)
            }
            Spacer()
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        // Marks the card at a glance, whatever it reads, so it is drawn in every state — W21's.
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "bolt.fill")
                .font(.title2)
                .foregroundStyle(Color.cyTextSecondary)
                .padding(Spacing.sm)
        }
        .background(Color.cyBgSecondary)
        .widgetDetail(label: CaloriesDashboardWidget.title, value: accessibilityValue) {
            CaloriesSheet(metrics: metrics)
        }
    }

    /// What VoiceOver reads after "Active Calories" (#361): "412 kilocalories", or why there is no
    /// estimate.
    var accessibilityValue: String {
        if let kilocalories { return CaloriesMetrics.spoken(kilocalories) }
        return rider == .noBodyMass ? "No weight in Health" : "No estimate yet"
    }
}

// MARK: - Previews

#Preview("Long ride") {
    CaloriesWidget(kilocalories: CaloriesMetrics.sampleLong.latest?.kilocalories, rider: CaloriesMetrics.sampleLong.rider)
        .frame(width: 196, height: 96)
}

#Preview("Early ride") {
    CaloriesWidget(kilocalories: CaloriesMetrics.sampleEarly.latest?.kilocalories, rider: CaloriesMetrics.sampleEarly.rider)
        .frame(width: 196, height: 96)
}

#Preview("No body mass") {
    CaloriesWidget(kilocalories: nil, rider: .noBodyMass)
        .frame(width: 196, height: 96)
}

#Preview("Long ride — Dark") {
    CaloriesWidget(kilocalories: CaloriesMetrics.sampleLong.latest?.kilocalories, rider: CaloriesMetrics.sampleLong.rider)
        .frame(width: 196, height: 96)
        .preferredColorScheme(.dark)
}

#Preview("Early ride — Dark") {
    CaloriesWidget(kilocalories: CaloriesMetrics.sampleEarly.latest?.kilocalories, rider: CaloriesMetrics.sampleEarly.rider)
        .frame(width: 196, height: 96)
        .preferredColorScheme(.dark)
}

#Preview("No body mass — Dark") {
    CaloriesWidget(kilocalories: nil, rider: .noBodyMass)
        .frame(width: 196, height: 96)
        .preferredColorScheme(.dark)
}
