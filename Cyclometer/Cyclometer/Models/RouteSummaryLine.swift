import Foundation

/// A route in one scannable line (#252). For example:
/// `72.4 km | 1,158 m gain | 2x Cat 2 climbs | Max 14% grade | Rolling, paved`.
///
/// Formatted at display time from the stored analysis, never stored itself: the units follow
/// the S12 picker, and a stored string would be wrong the moment the rider changed it.
enum RouteSummaryLine {

    /// #252's limit. A line past it wraps on S20 and truncates on S19.
    static let maximumLength = 80
    static let separator = " | "

    /// `includesDistance: false` is S19's row, where distance is already the trailing number.
    static func text(for route: RouteSummary, unit: UnitSystem, includesDistance: Bool = true) -> String {
        // Written in display order, each with its priority: when the line is too long, the
        // least important goes first. Max grade and the climb count are the detail; distance,
        // gain and what the road is like are the summary.
        var segments: [(priority: Int, text: String)] = []
        if includesDistance {
            segments.append((0, distanceLabel(route.distanceMeters, unit)))
        }
        if let gain = route.elevationGainMeters {
            segments.append((1, "\(elevationLabel(gain, unit)) gain"))
        }
        if let climbs = route.terrain.flatMap(climbsText) {
            segments.append((3, climbs))
        }
        if let terrain = route.terrain {
            segments.append((4, "Max \(terrain.maxGradePercent.formatted(.number.precision(.fractionLength(0))))% grade"))
        }
        if let character = characterText(route) {
            segments.append((2, character))
        }

        while joined(segments).count > maximumLength,
              let least = segments.indices.max(by: { segments[$0].priority < segments[$1].priority }) {
            segments.remove(at: least)
        }
        return joined(segments)
    }

    private static func joined(_ segments: [(priority: Int, text: String)]) -> String {
        segments.map(\.text).joined(separator: separator)
    }

    /// The hardest category and how many of it: "2x Cat 2 climbs". The easier climbs are left
    /// out — the hardest is what a rider plans around.
    private static func climbsText(_ terrain: RouteTerrainAnalysis) -> String? {
        guard let hardest = terrain.climbs.map(\.category).max() else { return nil }
        let count = terrain.climbs.filter { $0.category == hardest }.count
        return "\(count)x \(hardest.label) \(count == 1 ? "climb" : "climbs")"
    }

    /// "Rolling, paved", "Hilly", or "Gravel" when the route has a surface but no elevation.
    private static func characterText(_ route: RouteSummary) -> String? {
        let surface = route.surface?.dominant.map(surfaceText)
        switch (route.terrain?.character.label, surface) {
        case let (character?, surface?): return "\(character), \(surface)"
        case let (character?, nil): return character
        case let (nil, surface?): return surface.prefix(1).uppercased() + surface.dropFirst()
        case (nil, nil): return nil
        }
    }

    static func surfaceText(_ surface: SurfaceClass) -> String {
        surface == .unknown ? "mixed surface" : surface.rawValue
    }
}
