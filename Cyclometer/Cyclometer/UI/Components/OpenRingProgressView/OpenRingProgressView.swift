import SwiftUI
import Charts

/// Donut-style route-completion ring (Swift Charts `SectorMark`, 84% arc with a
/// gap at the bottom). When `progress` is `nil` (no route being followed), a bicycle
/// SF Symbol replaces the ring per S05.3.
struct OpenRingProgressView: View {
    private struct Segment: Identifiable {
        let id: String; let value: Double; let color: Color
    }
    let progress: Double?
    /// The percentage in the ring's hole. Off where the ring is too small to read it, as in the
    /// Dynamic Island (#310); VoiceOver still reads it.
    var showsPercent = true

    private func segments(for progress: Double) -> [Segment] {
        let arc = 0.84
        return [
            Segment(id: "complete",  value: max(progress * arc, 0.001),         color: .cyPrimary),
            Segment(id: "remaining", value: max((1 - progress) * arc, 0.001),   color: .secondary.opacity(0.22)),
            Segment(id: "gap",       value: 1 - arc,                            color: .clear)
        ]
    }

    /// The nearest percent, except that 100% waits for the finish: 99.5% of a 100 km route
    /// is still 500 m to ride.
    private func percent(_ progress: Double) -> Int {
        progress < 1 ? min(Int((progress * 100).rounded()), 99) : 100
    }

    var body: some View {
        if let progress {
            ZStack {
                Chart(segments(for: progress)) { s in
                    SectorMark(angle: .value("", s.value), innerRadius: .ratio(0.68),
                               outerRadius: .ratio(1), angularInset: s.id == "gap" ? 0 : 1)
                    .cornerRadius(Spacing.cornerSm)
                    .foregroundStyle(s.color)
                }
                .chartLegend(.hidden)
                .rotationEffect(.degrees(90))

                if showsPercent {
                    Text("\(percent(progress))%")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        // Narrower than the ring's hole, so "100%" shrinks inside it rather than
                        // running over the arc (#404).
                        .padding(.horizontal, Spacing.sm)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Route \(percent(progress)) percent complete")
        } else {
            Image(systemName: "figure.outdoor.cycle")
                .font(.title3)
                .foregroundStyle(.cyPrimary)
        }
    }
}

// MARK: - Previews

#Preview("Route") {
    OpenRingProgressView(progress: 0.42)
        .frame(width: Spacing.xxxl, height: Spacing.xxxl)
}

#Preview("Route complete") {
    OpenRingProgressView(progress: 1)
        .frame(width: Spacing.xxxl, height: Spacing.xxxl)
}

#Preview("No route") {
    OpenRingProgressView(progress: nil)
        .frame(width: Spacing.xxxl, height: Spacing.xxxl)
}

#Preview("No percent") {
    OpenRingProgressView(progress: 0.42, showsPercent: false)
        .frame(width: Spacing.islandStatusMark, height: Spacing.islandStatusMark)
}
