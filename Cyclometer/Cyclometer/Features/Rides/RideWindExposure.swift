import Foundation

/// The rider's direction of travel at one moving second of a finished ride (#151).
struct TimedHeading: Equatable, Sendable {
    var date: Date
    /// Degrees clockwise from true north, 0..<360.
    var degrees: Double
}

extension TimedHeading {
    /// How far back a bearing is measured from. Track points carry no course, so it comes from
    /// the coordinates, and between fixes a second apart GPS wander would swing it wildly.
    static let baselineMeters = 20.0

    /// One heading per moving second of the track: each point above `stationarySpeedMPS`, the
    /// same rule `PaceSplits` replays, so the shares are of the ride's Moving Time. The bearing is
    /// from the latest point at least `baselineMeters` back in the same stretch of riding, so it
    /// never spans a pause. The first `baselineMeters` of each stretch have none.
    static func movingHeadings(_ points: [TrackPointDTO]) -> [TimedHeading] {
        var headings: [TimedHeading] = []
        for segment in TrackPointDTO.segments(of: points) {
            var anchor = 0
            for (index, point) in segment.enumerated() {
                let here = point.coordinate
                // Move the anchor up to the last point still `baselineMeters` away.
                while anchor + 1 < index,
                      RouteGeometry.segmentMeters(from: segment[anchor + 1].coordinate, to: here) >= baselineMeters {
                    anchor += 1
                }
                guard let mps = point.speedMPS, mps > ActiveRideFeature.stationarySpeedMPS,
                      anchor < index,
                      RouteGeometry.segmentMeters(from: segment[anchor].coordinate, to: here) >= baselineMeters,
                      let bearing = RouteGeometry.bearingDegrees(from: segment[anchor].coordinate, to: here)
                else { continue }
                headings.append(TimedHeading(date: point.timestamp, degrees: bearing))
            }
        }
        return headings
    }
}

private extension TrackPointDTO {
    var coordinate: RouteCoordinate { RouteCoordinate(latitude: latitude, longitude: longitude) }
}

/// How the wind met the rider over a finished ride (#151): the share of moving time spent riding
/// into it, across it and with it, for S15's Weather section.
enum RideWindExposure: Equatable, Sendable {
    /// Whole percents that add up to 100.
    case shares(headwind: Int, crosswind: Int, tailwind: Int)
    /// Every recorded wind was too light to have a direction worth naming.
    case calm

    /// Below this a wind has no direction worth naming: under 2 km/h, about 1 mph.
    static let calmMPS = 0.5

    /// Each moving second takes the latest sample at or before it; seconds before the first
    /// sample take the first, since the first forecast of a ride arrives a fix or two in. Seconds
    /// under a calm sample aren't counted. Nil with no samples, or no headings to set them
    /// against (no track, or one that never moved).
    init?(headings: [TimedHeading], samples: [RideWeatherSample]) {
        guard !samples.isEmpty, !headings.isEmpty else { return nil }
        let samples = samples.sorted { $0.date < $1.date }
        var sampleIndex = 0
        var head = 0, cross = 0, tail = 0
        for heading in headings {
            while sampleIndex + 1 < samples.count, samples[sampleIndex + 1].date <= heading.date {
                sampleIndex += 1
            }
            let sample = samples[sampleIndex]
            guard sample.windSpeedMPS >= Self.calmMPS else { continue }
            switch RelativeWind(windFrom: sample.windFromDegrees, course: heading.degrees) {
            case .headwind: head += 1
            case .tailwind: tail += 1
            case .crosswindFromLeft, .crosswindFromRight: cross += 1
            }
        }
        // Every heading falls under some sample, so none counted means every one was calm.
        guard head + cross + tail > 0 else {
            self = .calm
            return
        }
        let percents = Self.wholePercents([head, cross, tail])
        self = .shares(headwind: percents[0], crosswind: percents[1], tailwind: percents[2])
    }

    /// Largest-remainder rounding, so the three shares always add up to 100. Ties go to the
    /// earlier count.
    static func wholePercents(_ counts: [Int]) -> [Int] {
        let total = counts.reduce(0, +)
        guard total > 0 else { return counts.map { _ in 0 } }
        let exact = counts.map { Double($0) * 100 / Double(total) }
        var percents = exact.map { Int($0.rounded(.down)) }
        let order = exact.indices.sorted { lhs, rhs in
            let left = exact[lhs] - Double(percents[lhs]), right = exact[rhs] - Double(percents[rhs])
            return left != right ? left > right : lhs < rhs
        }
        for index in order.prefix(100 - percents.reduce(0, +)) {
            percents[index] += 1
        }
        return percents
    }
}
