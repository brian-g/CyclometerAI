import Foundation

/// One of the eight compass points a bearing rounds to (#149): how the wind's direction is named
/// beside its arrow ("W" for a westerly).
enum CompassPoint: String, CaseIterable, Sendable {
    case north = "N", northEast = "NE", east = "E", southEast = "SE"
    case south = "S", southWest = "SW", west = "W", northWest = "NW"

    /// The nearest point to `degrees`, clockwise from true north. Any angle is accepted: −90° and
    /// 270° are both west.
    init(degrees: Double) {
        let points = Self.allCases
        let sector = 360 / Double(points.count)
        let normalized = degrees.truncatingRemainder(dividingBy: 360) + (degrees < 0 ? 360 : 0)
        // Each point owns the half-sector either side of it, so north runs from −22.5° to 22.5°.
        let index = Int((normalized / sector).rounded(.toNearestOrAwayFromZero)) % points.count
        self = points[index]
    }

    var abbreviation: String { rawValue }
}
