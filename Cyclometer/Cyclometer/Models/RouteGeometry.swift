import Foundation

/// Arithmetic over an imported route's polyline, run once at import and stored on
/// `Route`. `ImportedRoute` deliberately carries none of this (`ImportedRoute.swift:6-8`)
/// — the parser reads the file, this derives from what it read.
enum RouteGeometry {

    /// Elevation moves smaller than this are terrain-model noise, not climbing.
    ///
    /// GPX elevation is usually a digital elevation model sampled once per point, and
    /// summing every positive delta over that jitter reports far more ascent than the
    /// tool the rider planned in showed them for the same file. On S20 that reads as a
    /// bug rather than as a rounding difference, so gain is accumulated with hysteresis
    /// against this floor instead.
    static let elevationNoiseThresholdMeters = 3.0

    /// Length of the polyline, summed segment by segment.
    ///
    /// Deliberately *not* `CLLocation.distance(from:)`, which was the first implementation.
    /// It returned two different answers for the same polyline inside one test process — a
    /// relative difference of ~1.2e-5, the signature of a spherical model standing in for
    /// an ellipsoidal one before something in CoreLocation finished loading. For a number
    /// that is stored, shown to the rider and filtered on by #194, "occasionally 70 cm
    /// different depending on when you imported" is not acceptable, and it is not
    /// something a caller can defend against.
    ///
    /// This is pure arithmetic instead: deterministic, allocation-free, and agreeing with
    /// `CLLocation` to 0.04 m over a 100 km route sampled every 10 m.
    static func distanceMeters(_ coordinates: [RouteCoordinate]) -> Double {
        var total = 0.0
        for (start, end) in zip(coordinates, coordinates.dropFirst()) {
            total += segmentMeters(from: start, to: end)
        }
        return total
    }

    /// WGS84's semi-major axis and first eccentricity squared — the ellipsoid GPS reports against.
    private static let equatorialRadiusMeters = 6_378_137.0
    private static let eccentricitySquared = 0.006_694_379_990_141_316

    /// One segment as metres north and east on the tangent plane at its mean latitude.
    ///
    /// A route's points are metres to tens of metres apart, so over a single segment the
    /// ellipsoid is flat to far better than the precision anyone cares about — provided
    /// the two radii of curvature are taken at the segment's own latitude rather than
    /// assuming a sphere. That is what makes this match the reference to centimetres
    /// while a mean-radius haversine would drift by hundreds of metres over a long route.
    ///
    /// Split out from `segmentMeters` because the same two components are a bearing:
    /// length is their hypotenuse, direction is `atan2(east, north)`. Deriving the bearing
    /// separately would mean a second, subtly different flattening of the same ellipsoid.
    static func tangentPlaneOffset(
        from start: RouteCoordinate,
        to end: RouteCoordinate
    ) -> (north: Double, east: Double) {
        let meanLatitude = ((start.latitude + end.latitude) / 2) * .pi / 180
        let sinLatitude = sin(meanLatitude)
        let w = 1 - eccentricitySquared * sinLatitude * sinLatitude

        // Radius of curvature along the meridian (north-south) and the prime vertical (east-west).
        let meridional = equatorialRadiusMeters * (1 - eccentricitySquared) / (w * w.squareRoot())
        let normal = equatorialRadiusMeters / w.squareRoot()

        return (
            north: meridional * (end.latitude - start.latitude) * .pi / 180,
            east: normal * cos(meanLatitude) * (end.longitude - start.longitude) * .pi / 180
        )
    }

    private static func segmentMeters(from start: RouteCoordinate, to end: RouteCoordinate) -> Double {
        let offset = tangentPlaneOffset(from: start, to: end)
        return (offset.north * offset.north + offset.east * offset.east).squareRoot()
    }

    /// Compass bearing of a segment, degrees clockwise from true north in `0..<360`.
    ///
    /// Undefined for a zero-length segment, which is why this returns nil there rather than
    /// `atan2(0, 0)`'s silent `0` — due north is a wrong answer that looks like a right one,
    /// and `GPXRouteImporter` does not dedupe consecutive identical points (it drops only
    /// non-finite and out-of-range ones), so zero-length segments do reach this.
    static func bearingDegrees(from start: RouteCoordinate, to end: RouteCoordinate) -> Double? {
        let offset = tangentPlaneOffset(from: start, to: end)
        guard offset.north != 0 || offset.east != 0 else { return nil }
        let degrees = atan2(offset.east, offset.north) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// Distance from the route start to each coordinate, one entry per coordinate.
    ///
    /// The prefix sums behind `distanceMeters`, kept rather than discarded: #192 places a
    /// maneuver by along-route distance and #197 snaps the rider to the polyline, and both
    /// would otherwise re-walk the route to answer "how far in is this point".
    static func cumulativeDistances(_ coordinates: [RouteCoordinate]) -> [Double] {
        guard !coordinates.isEmpty else { return [] }
        var distances = [0.0]
        distances.reserveCapacity(coordinates.count)
        for (start, end) in zip(coordinates, coordinates.dropFirst()) {
            distances.append(distances[distances.count - 1] + segmentMeters(from: start, to: end))
        }
        return distances
    }

    /// The polyline re-sampled at a fixed spacing along its length.
    ///
    /// The point of it is that everything computed downstream stops depending on how the
    /// source file happened to be sampled. A GPX may carry a point every 1 m or every 200 m,
    /// and #192's first design compared *array indices* to decide whether two turns were near
    /// each other — which silently merged two corners 200 m apart on a decimated file. After
    /// resampling, index distance is road distance and that class of bug cannot recur.
    ///
    /// Interpolation is linear in latitude/longitude: over one sub-`step` interval the
    /// difference from interpolating along the geodesic is far below the metre.
    static func resampled(
        _ coordinates: [RouteCoordinate],
        everyMeters step: Double
    ) -> [(coordinate: RouteCoordinate, distanceAlongRouteMeters: Double)] {
        guard step > 0, coordinates.count > 1 else { return [] }
        let cumulative = cumulativeDistances(coordinates)
        guard let total = cumulative.last, total > 0 else { return [] }

        var samples: [(coordinate: RouteCoordinate, distanceAlongRouteMeters: Double)] = []
        samples.reserveCapacity(Int(total / step) + 2)
        var segment = 0
        var distance = 0.0
        while distance <= total {
            while segment + 2 < coordinates.count, cumulative[segment + 1] < distance { segment += 1 }
            let spanned = cumulative[segment + 1] - cumulative[segment]
            let t = spanned <= 0 ? 0 : (distance - cumulative[segment]) / spanned
            let start = coordinates[segment]
            let end = coordinates[segment + 1]
            samples.append((
                coordinate: RouteCoordinate(
                    latitude: start.latitude + (end.latitude - start.latitude) * t,
                    longitude: start.longitude + (end.longitude - start.longitude) * t,
                    elevationMeters: nil
                ),
                distanceAlongRouteMeters: distance
            ))
            distance += step
        }
        return samples
    }

    /// Where `point` falls on the polyline: the nearest point on the nearest segment, how far
    /// along the route that is, and how far off the route `point` itself lies.
    ///
    /// Perpendicular projection rather than nearest vertex. A cue snapped to the closest
    /// *vertex* is off by up to half the point spacing — ~5 m on a 10 m-sampled route, which
    /// is half of the ±10 m budget PRD §8.6 gives #197 for firing a turn, spent before #197
    /// has done anything.
    static func projection(
        of point: RouteCoordinate,
        onto coordinates: [RouteCoordinate],
        cumulative: [Double]
    ) -> (coordinate: RouteCoordinate, distanceAlongRouteMeters: Double, offsetMeters: Double)? {
        guard coordinates.count > 1, cumulative.count == coordinates.count else { return nil }

        var best: (coordinate: RouteCoordinate, distanceAlongRouteMeters: Double, offsetMeters: Double)?
        for index in 0..<(coordinates.count - 1) {
            let start = coordinates[index]
            let end = coordinates[index + 1]

            // One frame for both vectors, anchored at the segment start. Taking the segment
            // from `tangentPlaneOffset(start, end)` and the cue from `(start, point)` would
            // flatten the ellipsoid at two different mean latitudes and quietly leave the dot
            // product non-orthogonal.
            let segment = tangentPlaneOffset(from: start, to: end)
            let toPoint = tangentPlaneOffset(from: start, to: point)

            let lengthSquared = segment.north * segment.north + segment.east * segment.east
            // A zero-length segment gives 0/0. NaN loses every comparison, so left unguarded
            // it would neither win nor lose the argmin — and as segment 0 it would seed `best`
            // and then never be displaced.
            let t = lengthSquared <= 0
                ? 0
                : min(max((toPoint.north * segment.north + toPoint.east * segment.east) / lengthSquared, 0), 1)

            let offsetNorth = toPoint.north - segment.north * t
            let offsetEast = toPoint.east - segment.east * t
            let offset = (offsetNorth * offsetNorth + offsetEast * offsetEast).squareRoot()
            guard best == nil || offset < best!.offsetMeters else { continue }

            best = (
                coordinate: RouteCoordinate(
                    latitude: start.latitude + (end.latitude - start.latitude) * t,
                    longitude: start.longitude + (end.longitude - start.longitude) * t,
                    elevationMeters: nil
                ),
                distanceAlongRouteMeters: cumulative[index] + lengthSquared.squareRoot() * t,
                offsetMeters: offset
            )
        }
        return best
    }

    /// Cumulative ascent and descent, or `nil` when no point in the route carries an
    /// elevation at all.
    ///
    /// The optional is the whole point: a GPX with no `<ele>` must not report a
    /// confident zero, while a route that genuinely *is* flat — elevations present, none
    /// of them changing — must report `0` rather than "unknown".
    ///
    /// Two samples, not one, is the bar for "measurable". A route where exactly one point
    /// carries an elevation has no delta to accumulate, so it would compute `(0, 0)` — the
    /// same confident zero standing in for absent data that #211 had to unpick out of the
    /// track-point sentinels.
    ///
    /// Hysteresis rather than a raw positive-delta sum: a move is banked only once it
    /// clears `elevationNoiseThresholdMeters` from the last banked *reference*, which is
    /// then moved. Filtering each delta individually instead would discard a real 500 m
    /// climb sampled in 0.5 m steps; moving the reference accumulates that in full while
    /// still rejecting jitter about a level road.
    static func elevationGainLoss(_ coordinates: [RouteCoordinate]) -> (gain: Double, loss: Double)? {
        let elevations = coordinates.compactMap(\.elevationMeters)
        guard elevations.count > 1, let first = elevations.first else { return nil }

        var gain = 0.0
        var loss = 0.0
        var reference = first
        for elevation in elevations.dropFirst() {
            let delta = elevation - reference
            if delta >= elevationNoiseThresholdMeters {
                gain += delta
                reference = elevation
            } else if delta <= -elevationNoiseThresholdMeters {
                loss -= delta
                reference = elevation
            }
        }
        return (gain, loss)
    }

    /// The polyline's extent, stored on `Route` so S19 can frame a map and #194 can test
    /// viewport intersection without decoding every route's polyline.
    ///
    /// Empty input yields a zero box rather than nil, because `Route` stores these as
    /// non-optional columns and `GPXRouteImporter` already rejects a file with no
    /// coordinates (`.noCoordinates`) — so the empty case is unreachable from import.
    static func boundingBox(_ coordinates: [RouteCoordinate]) -> RouteBounds {
        guard let first = coordinates.first else {
            return RouteBounds(minLatitude: 0, maxLatitude: 0, minLongitude: 0, maxLongitude: 0)
        }
        var bounds = RouteBounds(
            minLatitude: first.latitude,
            maxLatitude: first.latitude,
            minLongitude: first.longitude,
            maxLongitude: first.longitude
        )
        for coordinate in coordinates.dropFirst() {
            bounds.minLatitude = min(bounds.minLatitude, coordinate.latitude)
            bounds.maxLatitude = max(bounds.maxLatitude, coordinate.latitude)
            bounds.minLongitude = min(bounds.minLongitude, coordinate.longitude)
            bounds.maxLongitude = max(bounds.maxLongitude, coordinate.longitude)
        }
        return bounds
    }
}

/// A route's extent. Antimeridian crossing is not handled — a cycling route spanning
/// ±180° is not a case worth the arithmetic, and pretending otherwise would only make
/// the intersection test in #194 harder to read.
struct RouteBounds: Sendable, Equatable {
    var minLatitude: Double
    var maxLatitude: Double
    var minLongitude: Double
    var maxLongitude: Double
}

extension RouteBounds {
    /// The smallest box containing all of them, or nil for an empty collection — S19 frames
    /// its map on every saved route when it has no rider fix, and #194 needs the same union
    /// to decide what a viewport holds.
    static func union(_ bounds: [RouteBounds]) -> RouteBounds? {
        guard var combined = bounds.first else { return nil }
        for box in bounds.dropFirst() {
            combined.minLatitude = min(combined.minLatitude, box.minLatitude)
            combined.maxLatitude = max(combined.maxLatitude, box.maxLatitude)
            combined.minLongitude = min(combined.minLongitude, box.minLongitude)
            combined.maxLongitude = max(combined.maxLongitude, box.maxLongitude)
        }
        return combined
    }

    /// The middle of the box: where the map pins a route whose polyline it has not loaded,
    /// and the centre of the region S19 frames when it has no rider fix. A plain pair rather
    /// than a `CLLocationCoordinate2D`, keeping CoreLocation out of the model layer.
    var center: (latitude: Double, longitude: Double) {
        ((minLatitude + maxLatitude) / 2, (minLongitude + maxLongitude) / 2)
    }
}
