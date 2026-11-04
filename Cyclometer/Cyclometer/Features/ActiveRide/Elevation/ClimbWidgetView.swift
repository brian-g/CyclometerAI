import SwiftUI

// MARK: - W22 Climb

/// W22 — Climb 2×1 (#463): the route's climb the rider is on, or the next one, in W5's 2×1
/// arrangement over the climb's profile.
///
/// - On a climb: distance to the top as the hero; climbing left and the average grade on the right;
///   the profile with the part ridden darker.
/// - Between climbs: distance to the next climb's start; its length and gain; its profile.
/// - No route followed, no elevation, or no climb ahead: "—", still placed.
///
/// Tapping opens the Elevation sheet, as W14–W18 do.
struct ClimbWidget: View {
    /// `NavigationFeature.State.climbReading`; nil while no route is followed.
    let reading: ClimbReading?
    /// What the "—" means to VoiceOver.
    var hasRoute = true
    var isTurnByTurnEnabled = true
    var hasElevation = true
    let unit: UnitSystem
    var metrics: () -> ElevationMetrics = { ElevationMetrics() }

    /// One card whatever the reading, so a climb starting while the Elevation sheet is open doesn't
    /// replace the `.widgetDetail` presenting it (W18's rule).
    var body: some View {
        ZStack {
            if let climb {
                RouteProfileChart(profile: climb.profile, progress: ridden)
            }
            VStack(alignment: .leading, spacing: 0) {
                WidgetLabel(label)
                HStack(alignment: .lastTextBaseline, spacing: Spacing.lg) {
                    hero
                    Spacer()
                    stats
                }
                Spacer()
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cyBgSecondary)
        .widgetDetail(label: ClimbDashboardWidget.title, value: accessibilityValue) {
            ElevationSheet(metrics: metrics)
        }
    }

    // MARK: - Sub-Views

    @ViewBuilder
    private var hero: some View {
        switch reading {
        case .climbing(_, let metersToTop, _, _):
            distanceHero(metersToTop)
        case .next(_, let metersToStart):
            distanceHero(metersToStart)
        case .noClimbAhead, nil:
            HeroNumber("—", unit: "").heroNumberSize(.medium)
        }
    }

    private func distanceHero(_ meters: Double) -> some View {
        let distance = unit.turnDistance(fromMeters: meters)
        return HeroNumber(distance.value, unit: distance.unit).heroNumberSize(.medium)
    }

    @ViewBuilder
    private var stats: some View {
        switch reading {
        case .climbing(let climb, _, let metersToClimb, _):
            HeroNumber(unit.elevation(fromMeters: metersToClimb), decimals: 0, unit: unit.elevationLabel) {
                Text("To Climb").font(.caption)
            }
            .heroNumberSize(.small)
            HeroNumber(Self.averageGrade(climb.climb), unit: Grade.unit) { Text("Avg").font(.caption) }
                .heroNumberSize(.small)
        case .next(let climb, _):
            let length = unit.turnDistance(fromMeters: climb.climb.lengthMeters)
            HeroNumber(length.value, unit: length.unit) { Text("Length").font(.caption) }
                .heroNumberSize(.small)
            HeroNumber(unit.elevation(fromMeters: climb.climb.gainMeters), decimals: 0, unit: unit.elevationLabel) {
                Text("Gain").font(.caption)
            }
            .heroNumberSize(.small)
        case .noClimbAhead, nil:
            EmptyView()
        }
    }

    // MARK: - Computed Display Values

    private var climb: RouteClimb? {
        switch reading {
        case .climbing(let climb, _, _, _), .next(let climb, _): climb
        case .noClimbAhead, nil: nil
        }
    }

    /// How far up the drawn climb the rider is: nothing ridden on the one ahead.
    private var ridden: Double? {
        if case .climbing(_, _, _, let fraction) = reading { return fraction }
        return nil
    }

    private var label: String {
        switch reading {
        case .climbing(let climb, _, _, _): "Climb · \(climb.climb.category.label)"
        case .next(let climb, _): "Next Climb · \(climb.climb.category.label)"
        case .noClimbAhead, nil: "Climb"
        }
    }

    /// A climb's average is never negative, so it reads "6" rather than W16's signed "+6".
    static func averageGrade(_ climb: Climb) -> String {
        Int(climb.averageGradePercent.rounded()).formatted()
    }

    /// The category as VoiceOver says it: "category 3", "hors catégorie".
    static func spokenCategory(_ category: ClimbCategory) -> String {
        switch category {
        case .cat4: "category 4"
        case .cat3: "category 3"
        case .cat2: "category 2"
        case .cat1: "category 1"
        case .hc: "hors catégorie"
        }
    }

    /// What VoiceOver reads after "Climb" (#361): the reading in words, or why there is none.
    var accessibilityValue: String {
        switch reading {
        case .climbing(let climb, let metersToTop, let metersToClimb, _):
            return [
                Self.spokenCategory(climb.climb.category),
                "\(unit.spokenTurnDistance(fromMeters: metersToTop)) to the top",
                "\(unit.spokenElevation(fromMeters: metersToClimb)) to climb",
                "average \(Self.averageGrade(climb.climb)) percent",
            ].joined(separator: ", ")
        case .next(let climb, let metersToStart):
            return [
                "next climb \(Self.spokenCategory(climb.climb.category)) in \(unit.spokenTurnDistance(fromMeters: metersToStart))",
                "\(unit.spokenTurnDistance(fromMeters: climb.climb.lengthMeters)) long",
                "\(unit.spokenElevation(fromMeters: climb.climb.gainMeters)) of climbing",
            ].joined(separator: ", ")
        case .noClimbAhead:
            return hasElevation ? "No climbs ahead" : "No elevation"
        case nil:
            return RouteProgressReading.empty(hasRoute: hasRoute, isTurnByTurnEnabled: isTurnByTurnEnabled)
        }
    }
}

// MARK: - Previews

extension RouteClimb {
    /// A Cat 3: 2.1 km at 6.7%, from 120 m to 260 m, every 10 m — W22's previews and tests.
    static let sample = RouteClimb(
        Climb(
            startMeters: 0, lengthMeters: 2_100, gainMeters: 140, averageGradePercent: 6.7, maxGradePercent: 9,
            topElevationMeters: 260, category: .cat3
        ),
        smoothed: (0...210).map { 120 + 140 * sin(Double($0) / 210 * .pi / 2) },
        spacing: 10
    )!
}

private let previewClimbing = ClimbReading.climbing(.sample, metersToTop: 1_200, metersToClimb: 84, fraction: 0.43)
private let previewNext = ClimbReading.next(.sample, metersToStart: 3_400)

#Preview("On a Climb — Metric") {
    ClimbWidget(reading: previewClimbing, unit: .metric)
        .frame(width: 393, height: 96)
}

#Preview("On a Climb — Imperial") {
    ClimbWidget(reading: previewClimbing, unit: .imperial)
        .frame(width: 393, height: 96)
}

#Preview("Between Climbs — Metric") {
    ClimbWidget(reading: previewNext, unit: .metric)
        .frame(width: 393, height: 96)
}

#Preview("Between Climbs — Imperial") {
    ClimbWidget(reading: previewNext, unit: .imperial)
        .frame(width: 393, height: 96)
}

#Preview("No Climbs Ahead") {
    ClimbWidget(reading: .noClimbAhead, unit: .metric)
        .frame(width: 393, height: 96)
}

#Preview("No Route") {
    ClimbWidget(reading: nil, hasRoute: false, unit: .metric)
        .frame(width: 393, height: 96)
}

#Preview("On a Climb — Dark") {
    ClimbWidget(reading: previewClimbing, unit: .metric)
        .frame(width: 393, height: 96)
        .preferredColorScheme(.dark)
}

#Preview("Between Climbs — Dark") {
    ClimbWidget(reading: previewNext, unit: .imperial)
        .frame(width: 393, height: 96)
        .preferredColorScheme(.dark)
}
