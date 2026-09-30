import SwiftUI

// MARK: - W11 Pace Widget

/// W11 — Pace 1×1
struct PaceWidget: View {
    let speedMPS: Double
    let unit: UnitSystem

    private var pace: String {
        guard let paceSeconds = unit.paceSeconds(fromMPS: speedMPS) else { return "--:--" }
        let minutes = Int(paceSeconds) / 60
        let seconds = Int(paceSeconds) % 60
        let secondsStr = seconds < 10 ? "0\(seconds)" : "\(seconds)"
        return "\(minutes):\(secondsStr)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel("Pace")
            HeroNumber(pace, unit: unit.paceLabel).heroNumberSize(.medium)
            Spacer()
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cyBgSecondary)
    }
}
