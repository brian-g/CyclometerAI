import SwiftUI
import Charts

/// S05.3 — the compact "mini-player" strip shown above the TabBar via
/// `tabViewBottomAccessory` while the Active Ride Dashboard is minimized.
/// Stateless display: it renders values passed by `AppView` and reports taps
/// on "Open"; the ride lifecycle lives in `AppFeature`/`ActiveRideFeature`.
struct ActiveRideAccessoryView: View {
    /// Route completion 0…1. `nil` when no route is loaded → bicycle glyph.
    let progress: Double?
    let distanceMeters: Double
    let speedMPS: Double
    let elapsedSeconds: Int
    let unit: UnitSystem
    let onOpen: () -> Void

    /// `.inline` when the strip is collapsed into the TabBar (tabs scrolled),
    /// `.expanded` when shown full-width above it. Drives how much we can fit.
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    private var displayDistance: Double { unit.distance(fromMeters: distanceMeters) }
    private var displaySpeed: Double { unit.speed(fromMPS: speedMPS) }
    private var isCollapsed: Bool { placement == .inline }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            OpenRingProgressView(progress: progress)
                .frame(width: Spacing.xxxl, height: Spacing.xxxl) // 40pt ≈ S05.3 42pt

            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                HeroNumber(elapsedSeconds.formattedElapsed, unit: "").heroNumberSize(.small)
                HeroNumber(displayDistance, unit: unit.distanceLabel).heroNumberSize(.small)
                // Speed is dropped when collapsed into the TabBar — there isn't
                // room, and the overflow reads as clipped/ugly.
                if !isCollapsed {
                    HeroNumber(displaySpeed, unit: unit.speedLabel).heroNumberSize(.small)
                }
            }
            Spacer()

            Button("Open", action: onOpen)
                .buttonStyle(.borderedProminent)
        }
        .padding(0)
    }
}

/// Donut-style route-completion ring (Swift Charts `SectorMark`, 84% arc with a
/// gap at the bottom). When `progress` is `nil` (no route loaded), a bicycle
/// SF Symbol replaces the ring per S05.3.
private struct OpenRingProgressView: View {
    private struct Segment: Identifiable {
        let id: String; let value: Double; let color: Color
    }
    let progress: Double?

    private func segments(for progress: Double) -> [Segment] {
        let arc = 0.84
        return [
            Segment(id: "complete",  value: max(progress * arc, 0.001),         color: .cyPrimary),
            Segment(id: "remaining", value: max((1 - progress) * arc, 0.001),   color: .secondary.opacity(0.22)),
            Segment(id: "gap",       value: 1 - arc,                            color: .clear)
        ]
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

                Text("\(Int((progress * 100).rounded()))%")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
            }
        } else {
            Image(systemName: "figure.outdoor.cycle")
                .font(.title3)
                .foregroundStyle(.cyPrimary)
        }
    }
}

// MARK: - Previews

#Preview("No route (bicycle)") {
    ActiveRideAccessoryView(
        progress: nil, distanceMeters: 12300, speedMPS: 7.89, elapsedSeconds: 2340, unit: .imperial, onOpen: {}
    )
    .padding()
    .tint(.cyPrimary)   // AppView applies this globally on the TabView
}

#Preview("With route (metric)") {
    ActiveRideAccessoryView(
        progress: 0.42, distanceMeters: 12300, speedMPS: 7.89, elapsedSeconds: 2340, unit: .metric, onOpen: {}
    )
    .padding()
    .tint(.cyPrimary)   // AppView applies this globally on the TabView
}
