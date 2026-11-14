import Foundation

/// The wind map's arrow (#561): a shaft and a head pointing the way the wind blows, longer for a
/// stronger wind. A shaft so it can't be mistaken for the route's direction-of-travel triangles
/// (`RouteDirectionMarkers.arrowTriangle`).
///
/// Sized in screen points and drawn on the map plane in metres, as those triangles are (#341), so
/// it holds its size through a pinch and turns with a heading-up camera. The points-to-metres
/// scale comes from the map (`MapProxy.metersPerPoint(mapSize:)`).
enum WindArrowGeometry {
    /// The arrow's length for the lightest wind with a direction, in screen points.
    static let minimumLengthPoints = 16.0
    /// Its length from `fullLengthMPS` up, so a gale doesn't cross the map.
    static let maximumLengthPoints = 34.0
    /// Where the length stops growing: about 43 km/h, a wind few riders set out into.
    static let fullLengthMPS = 12.0
    static let shaftWidthPoints = 3.0
    static let headWidthPoints = 11.0
    static let headLengthPoints = 9.0

    /// How long the arrow is for a wind of `speedMPS`; nil below `RideWindExposure.calmMPS`, where
    /// a wind has no direction worth drawing.
    static func lengthPoints(speedMPS: Double) -> Double? {
        guard speedMPS.isFinite, speedMPS >= RideWindExposure.calmMPS else { return nil }
        let fraction = min((speedMPS - RideWindExposure.calmMPS) / (fullLengthMPS - RideWindExposure.calmMPS), 1)
        return minimumLengthPoints + (maximumLengthPoints - minimumLengthPoints) * fraction
    }

    /// The arrow's outline at `center`, for a wind blowing *from* `windFromDegrees` (WeatherKit's
    /// meteorological direction) at `speedMPS`, on a map where one point is `metersPerPoint`. Seven
    /// corners, tip first. Nil in a calm.
    static func polygon(
        center: RouteCoordinate,
        windFromDegrees: Double,
        speedMPS: Double,
        metersPerPoint: Double
    ) -> [RouteCoordinate]? {
        guard let length = lengthPoints(speedMPS: speedMPS), metersPerPoint > 0 else { return nil }
        // The wind blows toward the opposite of where it comes from.
        let bearing = (windFromDegrees + 180) * .pi / 180
        let ahead = (north: cos(bearing), east: sin(bearing))
        let right = (north: -sin(bearing), east: cos(bearing))
        func point(along: Double, across: Double) -> RouteCoordinate {
            let along = along * metersPerPoint
            let across = across * metersPerPoint
            return RouteGeometry.coordinate(
                offsetFrom: center,
                north: ahead.north * along + right.north * across,
                east: ahead.east * along + right.east * across
            )
        }
        let tip = length / 2
        let tail = -length / 2
        let neck = tip - headLengthPoints
        let shaft = shaftWidthPoints / 2
        let head = headWidthPoints / 2
        return [
            point(along: tip, across: 0),
            point(along: neck, across: head),
            point(along: neck, across: shaft),
            point(along: tail, across: shaft),
            point(along: tail, across: -shaft),
            point(along: neck, across: -shaft),
            point(along: neck, across: -head),
        ]
    }
}
