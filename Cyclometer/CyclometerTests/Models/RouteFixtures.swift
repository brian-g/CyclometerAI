import Foundation
@testable import Cyclometer

/// Routes built in metres rather than as literal coordinates — moved here from
/// `TurnDerivationTests` when #197's navigation suites needed the same thing.
///
/// At 36°N one ten-thousandth of a degree is 11.06 m of latitude but 8.95 m of longitude, so
/// "turn 90 degrees right" is not something a hand-written lat/lon pair says legibly. Walking a
/// path by bearing and distance inverts the tangent-plane arithmetic the code under test uses,
/// which makes the fixture an independent second route to the same geometry.
enum RouteFixtures {

    typealias Leg = (bearingDegrees: Double, meters: Double)

    static let origin = RouteCoordinate(latitude: 36.0, longitude: -80.0, elevationMeters: nil)

    /// `start`, then a point every `spacingMeters` along each leg in turn.
    static func path(
        from start: RouteCoordinate = origin,
        legs: [Leg],
        spacingMeters: Double = 5
    ) -> [RouteCoordinate] {
        var points = [start]
        for leg in legs {
            let steps = max(1, Int((leg.meters / spacingMeters).rounded()))
            let step = leg.meters / Double(steps)
            for _ in 0..<steps {
                points.append(offset(points[points.count - 1], bearingDegrees: leg.bearingDegrees, meters: step))
            }
        }
        return points
    }

    /// The point `meters` from `start` on `bearingDegrees`, flattening the WGS84 ellipsoid at
    /// `start`'s latitude — exact to well under a millimetre over the few metres `path` steps.
    static func offset(_ start: RouteCoordinate, bearingDegrees: Double, meters: Double) -> RouteCoordinate {
        let latitude = start.latitude * .pi / 180
        let sinLatitude = sin(latitude)
        let w = 1 - 0.006_694_379_990_141_316 * sinLatitude * sinLatitude
        let meridional = 6_378_137.0 * (1 - 0.006_694_379_990_141_316) / (w * w.squareRoot())
        let normal = 6_378_137.0 / w.squareRoot()
        return RouteCoordinate(
            latitude: start.latitude + (meters * cos(bearingDegrees * .pi / 180) / meridional) * 180 / .pi,
            longitude: start.longitude + (meters * sin(bearingDegrees * .pi / 180) / (normal * cos(latitude))) * 180 / .pi,
            elevationMeters: nil
        )
    }

    /// Where a rider `meters` along `legs` would be, `lateralMeters` to the right of their
    /// direction of travel (negative is left).
    ///
    /// Past the last leg it carries on along the last bearing, as a rider who rides on beyond the
    /// end of a route does.
    static func point(
        along legs: [Leg],
        at meters: Double,
        lateralMeters: Double = 0,
        from start: RouteCoordinate = origin
    ) -> RouteCoordinate {
        var point = start
        var remaining = meters
        var bearing = legs.first?.bearingDegrees ?? 0
        for leg in legs where remaining > 0 {
            bearing = leg.bearingDegrees
            let step = min(remaining, leg.meters)
            point = offset(point, bearingDegrees: bearing, meters: step)
            remaining -= step
        }
        if remaining > 0 { point = offset(point, bearingDegrees: bearing, meters: remaining) }
        guard lateralMeters != 0 else { return point }
        return offset(point, bearingDegrees: bearing + 90, meters: lateralMeters)
    }

    /// The bearing of the leg `meters` along `legs` — the course a rider there is riding. At a
    /// boundary it is the leg just finished, matching `point(along:at:)`'s sideways offset; past the
    /// end, the last leg's.
    static func bearing(along legs: [Leg], at meters: Double) -> Double {
        var remaining = meters
        for leg in legs {
            if remaining <= leg.meters { return leg.bearingDegrees }
            remaining -= leg.meters
        }
        return legs.last?.bearingDegrees ?? 0
    }

    /// A clean fix at `coordinate`: accuracy well inside `GPSFixFilter`'s gate. `course` is
    /// CoreLocation's, so `-1` means it has none.
    static func fix(
        _ coordinate: RouteCoordinate,
        speed: Double,
        at timestamp: Date,
        course: Double = -1,
        horizontalAccuracy: Double = 5
    ) -> LocationUpdate {
        LocationUpdate(
            coordinate: Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude),
            altitude: 0,
            speed: speed,
            horizontalAccuracy: horizontalAccuracy,
            heading: course,
            timestamp: timestamp
        )
    }
}
