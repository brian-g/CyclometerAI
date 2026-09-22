import Foundation

/// What an imported route's elevation says about riding it (#252): its steepest grade, its
/// categorized climbs and one word for the whole thing. Derived once at import and stored on
/// `Route`, because S19's row reads it for every route in the list.
struct RouteTerrainAnalysis: Codable, Sendable, Equatable {
    /// The steepest smoothed grade anywhere on the route, over `RouteTerrain.gradeWindowMeters`.
    var maxGradePercent: Double
    /// Categorized climbs only, in ride order. A rise too small to reach Cat 4 is terrain, not
    /// a climb anyone would name, and listing it would bury the ones that matter.
    var climbs: [Climb]
    var character: RouteCharacter

    /// The climb with the highest FIETS score — what S20 quotes as the route's hardest.
    var hardestClimb: Climb? { climbs.max { $0.fiets < $1.fiets } }
}

struct Climb: Codable, Sendable, Equatable {
    /// Where the climb starts, measured along the route.
    var startMeters: Double
    var lengthMeters: Double
    var gainMeters: Double
    var averageGradePercent: Double
    var maxGradePercent: Double
    /// The altitude at the summit, which is what FIETS's high-altitude term reads.
    var topElevationMeters: Double
    var category: ClimbCategory

    /// The Dutch cycling magazine's climb difficulty index: `H² / (D × 10) + (T − 1000) / 1000`,
    /// with H the height gained and D the length, both in metres, and T the summit altitude.
    /// The altitude term applies only above 1,000 m.
    ///
    /// Per climb, not per route. #252 wrote it over whole-route totals, but the index was
    /// calibrated on single climbs (Alpe d'Huez is about 9.2) and summing a route's gain into
    /// one H produces a number nothing can be compared against.
    var fiets: Double {
        guard lengthMeters > 0 else { return 0 }
        let altitude = max(0, (topElevationMeters - 1_000) / 1_000)
        return gainMeters * gainMeters / (lengthMeters * 10) + altitude
    }
}

/// The Tour de France style categories, on Strava's published scale: length in metres times
/// average grade in percent. Hardest last, so `max()` is the hardest.
enum ClimbCategory: String, Codable, Sendable, Equatable, Comparable, CaseIterable {
    case cat4, cat3, cat2, cat1, hc

    /// The lowest score that earns each category.
    var minimumScore: Double {
        switch self {
        case .cat4: 8_000
        case .cat3: 16_000
        case .cat2: 32_000
        case .cat1: 64_000
        case .hc: 80_000
        }
    }

    init?(score: Double) {
        guard let category = Self.allCases.last(where: { score >= $0.minimumScore }) else { return nil }
        self = category
    }

    var label: String {
        switch self {
        case .cat4: "Cat 4"
        case .cat3: "Cat 3"
        case .cat2: "Cat 2"
        case .cat1: "Cat 1"
        case .hc: "HC"
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.minimumScore < rhs.minimumScore
    }
}

enum RouteCharacter: String, Codable, Sendable, Equatable, CaseIterable {
    case flat, rolling, hilly, mountainous, punchy

    var label: String { rawValue.capitalized }
}

/// The arithmetic behind `RouteTerrainAnalysis`. Pure, so every threshold below is pinned by
/// `RouteTerrainTests` rather than by a screenshot.
enum RouteTerrain {

    /// The spacing the elevation is resampled to before anything else, so nothing downstream
    /// depends on how densely the source file happened to be sampled.
    static let sampleSpacingMeters = 10.0

    /// A centred moving average over this span takes out the step noise of a terrain model
    /// sampled point by point.
    static let smoothingWindowMeters = 50.0

    /// Grade is rise over this run. #252 asked for a 3–5 second window, but a planned route has
    /// no timestamps, so the window is a distance. It is longer than 3–5 s at riding speed
    /// (20–50 m) because a route file's elevation comes from a terrain model, and over 20 m one
    /// bad point in that model reads as a 40% wall.
    static let gradeWindowMeters = 100.0

    /// A descent smaller than this does not end a climb. Real climbs level off and dip for a
    /// few metres, and splitting a Cat 1 into two Cat 3s at every false flat would misdescribe
    /// the road. Larger than `RouteGeometry.elevationNoiseThresholdMeters` on purpose: that one
    /// separates noise from terrain, this one separates one climb from the next.
    static let climbDipToleranceMeters = 10.0

    /// A rise's low point can sit anywhere in the valley before it, which on a level lead-in
    /// may be kilometres back, and its high point anywhere on the plateau after. Each end is
    /// pulled in to the last (first) point within this much of it, so a climb starts where the
    /// road starts to rise — at the cost of at most this much gain at either end.
    static let climbEndTrimMeters = 1.0

    /// Strava's floor for a categorized climb.
    static let minimumClimbAverageGradePercent = 3.0
    static let minimumClimbLengthMeters = 500.0

    /// Gain per kilometre at which the route's character steps up.
    static let rollingGainPerKilometer = 5.0
    static let hillyGainPerKilometer = 10.0
    static let mountainousGainPerKilometer = 20.0

    /// A "kick": a short, steep rise. One every `punchyKickSpacingMeters` on a route that is
    /// not flat and has no big climbs makes it punchy.
    static let kickMinimumGradePercent = 8.0
    static let kickMinimumLengthMeters = 100.0
    static let kickMaximumLengthMeters = 1_000.0
    static let punchyKickSpacingMeters = 10_000.0

    /// Nil under exactly the rule `RouteGeometry.elevationGainLoss` uses (fewer than two points
    /// with an elevation), so S20's summary and its gain and loss rows cannot disagree about
    /// whether a route has elevation at all.
    static func analyze(_ coordinates: [RouteCoordinate]) -> RouteTerrainAnalysis? {
        let total = RouteGeometry.distanceMeters(coordinates)
        guard total > 0, let gain = RouteGeometry.elevationGainLoss(coordinates)?.gain else { return nil }

        let count = Int(total / sampleSpacingMeters) + 1
        guard let raw = RouteGeometry.elevationProfile(coordinates, sampleCount: count) else { return nil }
        // `elevationProfile` never returns fewer than two samples, so this never divides by zero.
        let spacing = total / Double(raw.count - 1)

        let elevation = movingAverage(raw, halfWindow: Int((smoothingWindowMeters / 2 / spacing).rounded()))
        let grades = grades(elevation, spacing: spacing)
        let rises = rises(elevation, tolerance: climbDipToleranceMeters)
            .map { trimmed($0, elevation, tolerance: climbEndTrimMeters) }

        let climbs: [Climb] = rises.compactMap { rise in
            let length = Double(rise.top - rise.bottom) * spacing
            let height = elevation[rise.top] - elevation[rise.bottom]
            guard length >= minimumClimbLengthMeters else { return nil }
            let average = height / length * 100
            guard average >= minimumClimbAverageGradePercent,
                  let category = ClimbCategory(score: length * average)
            else { return nil }
            return Climb(
                startMeters: Double(rise.bottom) * spacing,
                lengthMeters: length,
                gainMeters: height,
                averageGradePercent: average,
                maxGradePercent: grades[rise.bottom...rise.top].max() ?? average,
                topElevationMeters: elevation[rise.top],
                category: category
            )
        }

        let kicks = rises.filter { rise in
            let length = Double(rise.top - rise.bottom) * spacing
            guard length >= kickMinimumLengthMeters, length < kickMaximumLengthMeters else { return false }
            return (elevation[rise.top] - elevation[rise.bottom]) / length * 100 >= kickMinimumGradePercent
        }.count

        return RouteTerrainAnalysis(
            maxGradePercent: grades.max() ?? 0,
            climbs: climbs,
            character: character(gainPerKilometer: gain / (total / 1_000),
                                 hardestCategory: climbs.map(\.category).max(),
                                 kicksPer10Kilometers: Double(kicks) / (total / punchyKickSpacingMeters))
        )
    }

    static func character(
        gainPerKilometer: Double,
        hardestCategory: ClimbCategory?,
        kicksPer10Kilometers: Double
    ) -> RouteCharacter {
        if gainPerKilometer >= mountainousGainPerKilometer || hardestCategory.map({ $0 >= .cat1 }) == true {
            return .mountainous
        }
        if gainPerKilometer < rollingGainPerKilometer { return .flat }
        if kicksPer10Kilometers >= 1 { return .punchy }
        return gainPerKilometer < hillyGainPerKilometer ? .rolling : .hilly
    }

    // MARK: - Steps

    /// `rise` with its bottom moved up to the last point still within `tolerance` of the low,
    /// and its top moved back to the first point within `tolerance` of the high.
    static func trimmed(_ rise: (bottom: Int, top: Int), _ elevation: [Double],
                        tolerance: Double) -> (bottom: Int, top: Int) {
        let low = elevation[rise.bottom]
        let high = elevation[rise.top]
        let bottom = (rise.bottom...rise.top).last { elevation[$0] <= low + tolerance } ?? rise.bottom
        let top = (bottom...rise.top).first { elevation[$0] >= high - tolerance } ?? rise.top
        return (bottom, top)
    }

    /// Centred, shrinking at the ends rather than padding, so the first and last samples are
    /// averaged over what exists instead of over invented values.
    static func movingAverage(_ values: [Double], halfWindow: Int) -> [Double] {
        guard halfWindow > 0, values.count > 1 else { return values }
        var prefix = [0.0]
        prefix.reserveCapacity(values.count + 1)
        for value in values { prefix.append(prefix[prefix.count - 1] + value) }
        return values.indices.map { index in
            let lower = max(0, index - halfWindow)
            let upper = min(values.count - 1, index + halfWindow)
            return (prefix[upper + 1] - prefix[lower]) / Double(upper - lower + 1)
        }
    }

    /// Percent grade at each sample, as rise over the `gradeWindowMeters` centred on it. The
    /// window is clamped at the ends, and a route shorter than it gets one grade end to end.
    static func grades(_ elevation: [Double], spacing: Double) -> [Double] {
        guard elevation.count > 1, spacing > 0 else { return [] }
        let half = max(1, Int((gradeWindowMeters / 2 / spacing).rounded()))
        return elevation.indices.map { index in
            let lower = max(0, index - half)
            let upper = min(elevation.count - 1, index + half)
            return (elevation[upper] - elevation[lower]) / (Double(upper - lower) * spacing) * 100
        }
    }

    /// Every rise from a low to the next high, where a reversal only counts once it exceeds
    /// `tolerance`. The same hysteresis idea as `RouteGeometry.elevationGainLoss`: a dip smaller
    /// than the tolerance leaves one rise, not two.
    static func rises(_ elevation: [Double], tolerance: Double) -> [(bottom: Int, top: Int)] {
        guard elevation.count > 1 else { return [] }
        enum Trend { case unknown, up, down }

        var result: [(bottom: Int, top: Int)] = []
        var trend = Trend.unknown
        var lowest = 0
        var highest = 0
        // The last confirmed turning point, and the running extreme since it.
        var pivot = 0
        var extreme = 0

        for index in elevation.indices.dropFirst() {
            let value = elevation[index]
            switch trend {
            case .unknown:
                if value < elevation[lowest] { lowest = index }
                if value > elevation[highest] { highest = index }
                guard elevation[highest] - elevation[lowest] >= tolerance else { continue }
                if highest > lowest {
                    trend = .up
                    pivot = lowest
                    extreme = highest
                } else {
                    trend = .down
                    pivot = highest
                    extreme = lowest
                }
            case .up:
                if value > elevation[extreme] {
                    extreme = index
                } else if elevation[extreme] - value >= tolerance {
                    result.append((pivot, extreme))
                    pivot = extreme
                    extreme = index
                    trend = .down
                }
            case .down:
                if value < elevation[extreme] {
                    extreme = index
                } else if value - elevation[extreme] >= tolerance {
                    pivot = extreme
                    extreme = index
                    trend = .up
                }
            }
        }
        if trend == .up { result.append((pivot, extreme)) }
        return result
    }
}
