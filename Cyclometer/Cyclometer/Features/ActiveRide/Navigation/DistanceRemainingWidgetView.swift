import SwiftUI

// MARK: - W19 Distance Remaining Widget

/// W19 — Distance Remaining 1×1 (#461): how much of the route is left, read from
/// `NavigationFeature.remainingDistanceMeters`, to one decimal like W6. Tapping opens the map sheet,
/// as W9 does.
///
/// Always on the dashboard: with no route, turn-by-turn off, or no match on the route yet, it reads "—".
struct DistanceRemainingWidget: View {
    /// Nil while no route is being followed; 0 once it is complete.
    let remainingMeters: Double?
    let unit: UnitSystem
    /// What the "—" means to VoiceOver: no route, or one that isn't followed.
    var hasRoute = true
    var isTurnByTurnEnabled = true
    /// The map sheet, W8's. A closure so the dashboard never reads the (growing) track itself —
    /// only the presented sheet does (#362).
    var detail: () -> LiveMapSheet = {
        LiveMapSheet(trackSegments: [[]], route: [], orientation: .headingUp, onOrientationToggle: {})
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel("Distance Remaining")
            if let remainingMeters {
                HeroNumber(unit.distance(fromMeters: remainingMeters), unit: unit.distanceLabel).heroNumberSize(.medium)
            } else {
                HeroNumber("—", unit: "").heroNumberSize(.medium)
            }
            Spacer()
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.cyBgSecondary)
        .widgetDetail(label: DistanceRemainingDashboardWidget.title, value: accessibilityValue, detail)
    }

    /// What VoiceOver reads after "Distance Remaining" (#361).
    var accessibilityValue: String {
        remainingMeters.map { unit.spokenDistance(fromMeters: $0) }
            ?? RouteProgressReading.empty(hasRoute: hasRoute, isTurnByTurnEnabled: isTurnByTurnEnabled)
    }
}

// MARK: - Previews

#Preview("Mid-Route — Metric") {
    DistanceRemainingWidget(remainingMeters: 12_400, unit: .metric)
        .frame(width: 196, height: 96)
}

#Preview("Mid-Route — Imperial") {
    DistanceRemainingWidget(remainingMeters: 12_400, unit: .imperial)
        .frame(width: 196, height: 96)
}

#Preview("Complete") {
    DistanceRemainingWidget(remainingMeters: 0, unit: .metric)
        .frame(width: 196, height: 96)
}

#Preview("No Route") {
    DistanceRemainingWidget(remainingMeters: nil, unit: .metric, hasRoute: false)
        .frame(width: 196, height: 96)
}

#Preview("Mid-Route — Dark") {
    DistanceRemainingWidget(remainingMeters: 12_400, unit: .metric)
        .frame(width: 196, height: 96)
        .preferredColorScheme(.dark)
}
