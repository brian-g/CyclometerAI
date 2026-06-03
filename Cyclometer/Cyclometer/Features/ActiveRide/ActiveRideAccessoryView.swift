import SwiftUI
import Charts

struct ActiveRideAccessoryView: View {
    let distanceKM: Double
    let speedKPH: Double
    let onOpen: () -> Void
    let onDismiss: () -> Void

    private var distanceMi: Double { distanceKM * 0.621371 }
    private var speedMPH: Double { speedKPH * 0.621371 }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            OpenRingProgressView(progress: 0.42, percentage: 42)
                .frame(width: Spacing.xxxl, height: Spacing.xxxl)

            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                HeroNumber(distanceMi, unit: "mi").heroNumberSize(.small)
                HeroNumber(speedMPH, unit: "mph").heroNumberSize(.small)
            }
            Spacer()

            Button("Open", action: onOpen)
                .buttonStyle(.borderedProminent)
        }
        .padding(0)
    }
}

private struct OpenRingProgressView: View {
    private struct Segment: Identifiable {
        let id: String; let value: Double; let color: Color
    }
    let progress: Double
    let percentage: Int

    private var segments: [Segment] {
        let arc = 0.84
        return [
            Segment(id: "complete",  value: max(progress * arc, 0.001),         color: .accentColor),
            Segment(id: "remaining", value: max((1 - progress) * arc, 0.001),   color: .secondary.opacity(0.22)),
            Segment(id: "gap",       value: 1 - arc,                            color: .clear)
        ]
    }

    var body: some View {
        ZStack {
            Chart(segments) { s in
                SectorMark(angle: .value("", s.value), innerRadius: .ratio(0.68),
                           outerRadius: .ratio(1), angularInset: s.id == "gap" ? 0 : 1)
                .cornerRadius(Spacing.cornerSm)
                .foregroundStyle(s.color)
            }
            .chartLegend(.hidden)
            .rotationEffect(.degrees(90))

            Text("\(percentage)%")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
        }
    }
}
