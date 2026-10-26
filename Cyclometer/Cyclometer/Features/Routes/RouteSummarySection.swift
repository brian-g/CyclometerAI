import SwiftUI

/// S20's route summary card (#252): the one-line summary, then what it abbreviates.
///
/// Absent for a route with neither elevation nor a surface yet, where the line would only
/// repeat the Distance row above it. Every value takes `.monospacedDigit()` so figures line up
/// down the trailing edge and don't jitter when the surface lands after the screen opens.
struct RouteSummarySection: View {
    let summary: RouteSummary
    let unit: UnitSystem

    private var surface: RouteSurfaceBreakdown? {
        summary.surface.flatMap { $0.totalMeters > 0 ? $0 : nil }
    }

    var body: some View {
        if summary.terrain != nil || surface != nil {
            Section("Summary") {
                Text(RouteSummaryLine.text(for: summary, unit: unit))
                    .font(.headline)
                // The on-device paragraph (#203). Absent without Apple Intelligence, and the
                // section reads exactly as it did before.
                if let narrative = summary.narrative {
                    Text(narrative)
                        .font(.subheadline)
                        .foregroundStyle(Color.cyTextSecondary)
                }
                if let terrain = summary.terrain {
                    LabeledContent("Character", value: terrain.character.label)
                    LabeledContent("Max Grade", value: Self.percent(terrain.maxGradePercent))
                    if let hardest = terrain.hardestClimb {
                        LabeledContent("Hardest Climb (FIETS)",
                                       value: hardest.fiets.formatted(.number.precision(.fractionLength(1))))
                    }
                    ForEach(Array(terrain.climbs.enumerated()), id: \.offset) { _, climb in
                        LabeledContent(climb.category.label,
                                       value: "\(distanceLabel(climb.lengthMeters, unit)) at \(Self.percent(climb.averageGradePercent))")
                    }
                }
                if let surface {
                    LabeledContent("Surface", value: Self.surfaceText(surface))
                    // ODbL: data from OpenStreetMap is credited wherever it is shown.
                    Text("Surface data © OpenStreetMap contributors")
                        .font(.caption)
                        .foregroundStyle(Color.cyTextSecondary)
                }
            }
            .monospacedDigit()
        }
    }

    private static func percent(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0))))%"
    }

    /// "82% paved · 15% gravel · 3% unknown", largest first, classes with no share left out.
    static func surfaceText(_ surface: RouteSurfaceBreakdown) -> String {
        SurfaceClass.allCases
            .map { (surface: $0, fraction: surface.fraction($0)) }
            .filter { ($0.fraction * 100).rounded() > 0 }
            .sorted { $0.fraction > $1.fraction }
            .map { "\(percent($0.fraction * 100)) \($0.surface.rawValue)" }
            .joined(separator: " · ")
    }
}

// MARK: - Previews

private func summaryPreview(_ summary: RouteSummary, unit: UnitSystem = .imperial) -> some View {
    List { RouteSummarySection(summary: summary, unit: unit) }
}

#Preview("Narrative") {
    var route = RouteSummary.previewRoutes[1]
    route.narrative = RouteSummary.previewNarrative
    return summaryPreview(route)
}

#Preview("Narrative — metric") {
    var route = RouteSummary.previewRoutes[1]
    route.narrative = RouteSummary.previewNarrative
    return summaryPreview(route, unit: .metric)
}

/// A device without Apple Intelligence, or a narrative not written yet.
#Preview("No narrative") {
    summaryPreview(RouteSummary.previewRoutes[1])
}

/// A flat route, with no climbs and no surface looked up yet.
#Preview("Flat, no surface") {
    summaryPreview(RouteSummary.previewRoutes[2])
}
