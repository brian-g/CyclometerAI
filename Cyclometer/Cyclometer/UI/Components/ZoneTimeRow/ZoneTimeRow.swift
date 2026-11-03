import SwiftUI

// MARK: - Zone Time Row

/// One zone in a sheet's time-in-zones list (#145, #494): its dot in the colour its chart band and
/// donut slice are drawn in, its name over its range, and the ride's time in it. VoiceOver reads
/// it as one element, "name, range, time". The Heart rate and Cadence sheets share it.
struct ZoneTimeRow: View {
    let color: Color
    let name: String
    let range: MetricReading
    let time: MetricReading

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ZoneDot(color: color)
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                Text(range.shown)
                    .font(.footnote)
                    .foregroundStyle(Color.cyTextSecondary)
            }
            Spacer(minLength: Spacing.sm)
            Text(time.value)
                .monospacedDigit()
                .foregroundStyle(Color.cyTextSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue("\(range.spoken), \(time.spoken)")
    }
}

// MARK: - Zone Dot

/// A zone's colour as a small dot, keying a row or reading to the chart's band and donut's slice.
struct ZoneDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: Spacing.sm, height: Spacing.sm)
    }
}

// MARK: - Previews

private struct ZoneTimeRowPreview: View {
    var body: some View {
        List {
            Section("Time in Zones") {
                ZoneTimeRow(
                    color: .hrZone(1),
                    name: "Z1 Recovery/Light",
                    range: MetricReading(value: "60–137", unit: "bpm", spoken: "60 to 137 beats per minute"),
                    time: MetricReading(value: "0:05:12", spoken: "5 minutes, 12 seconds")
                )
                ZoneTimeRow(
                    color: .hrZone(5),
                    name: "Z5 Sprint",
                    range: MetricReading(value: "110+", unit: "rpm", spoken: "110 rpm or more"),
                    time: MetricReading(value: "0:00:42", spoken: "42 seconds")
                )
            }
        }
    }
}

#Preview("Rows") {
    ZoneTimeRowPreview()
}

#Preview("Rows — Dark") {
    ZoneTimeRowPreview()
        .preferredColorScheme(.dark)
}
