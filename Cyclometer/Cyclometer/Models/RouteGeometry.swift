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

    /// Where a point falls on a polyline: the nearest point on the route itself, how far along
    /// the route that is, how far off the route the point lies, and which segment it landed on.
    struct Projection: Equatable, Sendable {
        var coordinate: RouteCoordinate
        var distanceAlongRouteMeters: Double
        var offsetMeters: Double
        /// `coordinates[segmentIndex]` to `coordinates[segmentIndex + 1]`. #197 keeps it so the
        /// next fix's search is anchored where the last one matched.
        var segmentIndex: Int
    }

    /// Where `point` falls on the polyline: the nearest point on the nearest segment.
    ///
    /// Perpendicular projection rather than nearest vertex. A cue snapped to the closest
    /// *vertex* is off by up to half the point spacing — ~5 m on a 10 m-sampled route, which
    /// is half of the ±10 m budget PRD §8.6 gives #197 for firing a turn, spent before #197
    /// has done anything.
    ///
    /// `alongRoute` confines the search to the segments overlapping that stretch of the route.
    /// Nearest over the whole polyline is right for a cue, which has no prior position to go on,
    /// and wrong for a moving rider: the two legs of an out-and-back lie on the same road, so a
    /// rider still riding out is as near the way back — nearer, on the right of a two-way road —
    /// and snapping there would announce the return leg's turns (#197). `nil` searches every
    /// segment.
    ///
    /// `heading` skips segments running against it by more than a right angle. A window cannot
    /// tell the two legs of an out-and-back apart within half its width of the turnaround, where
    /// the way back falls inside it; the rider's course can, anywhere, because the legs run
    /// opposite ways. `nil` ignores direction, which is what a cue or a stationary rider needs.
    static func projection(
        of point: RouteCoordinate,
        onto coordinates: [RouteCoordinate],
        cumulative: [Double],
        alongRoute window: ClosedRange<Double>? = nil,
        heading: Double? = nil
    ) -> Projection? {
        guard coordinates.count > 1, cumulative.count == coordinates.count else { return nil }
        let segmentCount = coordinates.count - 1

        var segments = 0..<segmentCount
        if let window {
            // Prefix sums never decrease, so both ends of the window are a binary search away —
            // a window is a few hundred metres of a route that can run to tens of thousands of
            // points.
            let first = partitioningIndex(in: 0..<segmentCount) { cumulative[$0 + 1] >= window.lowerBound }
            let pastLast = partitioningIndex(in: 0..<segmentCount) { cumulative[$0] > window.upperBound }
            guard first < pastLast else { return nil }
            segments = first..<pastLast
        }

        let direction = unitVector(heading)
        var best: Projection?
        for index in segments {
            guard let candidate = segmentProjection(
                of: point, segment: index, coordinates: coordinates, cumulative: cumulative, direction: direction
            ), best == nil || candidate.offsetMeters < best!.offsetMeters
            else { continue }
            best = candidate
        }
        return best
    }

    /// The first stretch of the polyline, at or beyond `floor` metres in, that passes within
    /// `tolerance` of `point` — and the nearest point on that stretch.
    ///
    /// The earliest pass rather than the nearest, for a route that goes by the same place twice.
    /// Where the rider has no recent match to window around — the start of a ride, a return from
    /// off-route, a relaunch mid-ride — the nearer of two passes is decided by a metre of GPS
    /// scatter, while the first one after where the rider is known to have got to is the one they
    /// are on (#197). A stretch ends at the first segment that no longer comes within `tolerance`,
    /// so a later pass is never reached.
    ///
    /// `heading` works as it does for `projection`: a segment running against it neither starts
    /// nor continues a stretch.
    ///
    /// O(n) from the floor, unlike a windowed `projection` — which is why #197 asks it only while
    /// it has nothing to window around.
    static func firstPass(
        of point: RouteCoordinate,
        onto coordinates: [RouteCoordinate],
        cumulative: [Double],
        fromMeters floor: Double,
        within tolerance: Double,
        heading: Double? = nil
    ) -> Projection? {
        guard coordinates.count > 1, cumulative.count == coordinates.count else { return nil }
        let segmentCount = coordinates.count - 1
        let first = partitioningIndex(in: 0..<segmentCount) { cumulative[$0 + 1] >= floor }

        let direction = unitVector(heading)
        var best: Projection?
        for index in first..<segmentCount {
            guard let candidate = segmentProjection(
                of: point, segment: index, coordinates: coordinates, cumulative: cumulative, direction: direction
            ), candidate.offsetMeters <= tolerance
            else {
                if best != nil { break }
                continue
            }
            if best == nil || candidate.offsetMeters < best!.offsetMeters { best = candidate }
        }
        return best
    }

    /// A compass heading as a unit vector in the (north, east) frame `tangentPlaneOffset` works in.
    private static func unitVector(_ heading: Double?) -> (north: Double, east: Double)? {
        heading.map { (north: cos($0 * .pi / 180), east: sin($0 * .pi / 180)) }
    }

    /// `point` projected onto one segment — the arithmetic both searches above share. Nil when
    /// the segment runs against `direction` by more than a right angle.
    private static func segmentProjection(
        of point: RouteCoordinate,
        segment index: Int,
        coordinates: [RouteCoordinate],
        cumulative: [Double],
        direction: (north: Double, east: Double)?
    ) -> Projection? {
        let start = coordinates[index]
        let end = coordinates[index + 1]

        // One frame for both vectors, anchored at the segment start. Taking the segment
        // from `tangentPlaneOffset(start, end)` and the cue from `(start, point)` would
        // flatten the ellipsoid at two different mean latitudes and quietly leave the dot
        // product non-orthogonal.
        let segment = tangentPlaneOffset(from: start, to: end)
        // A dot product rather than a difference of bearings: there is no wraparound at north to
        // get wrong, and a zero-length segment — which has no direction — scores zero and is kept.
        if let direction, segment.north * direction.north + segment.east * direction.east < 0 {
            return nil
        }
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
        return Projection(
            coordinate: RouteCoordinate(
                latitude: start.latitude + (end.latitude - start.latitude) * t,
                longitude: start.longitude + (end.longitude - start.longitude) * t,
                elevationMeters: nil
            ),
            distanceAlongRouteMeters: cumulative[index] + lengthSquared.squareRoot() * t,
            offsetMeters: (offsetNorth * offsetNorth + offsetEast * offsetEast).squareRoot(),
            segmentIndex: index
        )
    }

    /// The first index in `range` at which `isPast` holds, for a predicate that keeps holding
    /// from there on — `range.upperBound` when it never does.
    private static func partitioningIndex(in range: Range<Int>, where isPast: (Int) -> Bool) -> Int {
        var low = range.lowerBound
        var high = range.upperBound
        while low < high {
            let middle = low + (high - low) / 2
            if isPast(middle) { high = middle } else { low = middle + 1 }
        }
        return low
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

    /// The route's elevation at `sampleCount` evenly spaced distances from start to finish — S20's
    /// elevation profile (#195) — or nil under exactly the rule `elevationGainLoss` uses, so the
    /// chart and the gain/loss rows beside it can never disagree about whether a route has
    /// elevation at all.
    ///
    /// Spaced by *distance*, not by point. `ElevationProfileView` plots its samples against their
    /// index, and even spacing is what lets that index read as distance along the road. Charting
    /// the file's own points instead would stretch a stretch sampled every metre across most of the
    /// chart and squeeze one sampled every 200 m into a sliver.
    ///
    /// The samples always span the whole route. A point without an elevation is interpolated
    /// across from the nearest points either side that have one, and the stretches before the
    /// first and after the last such point hold its value — so a file missing `<ele>` at one end
    /// still charts against the route's full length rather than against the part that was measured.
    ///
    /// Its own walk rather than `resampled(_:everyMeters:)`, which drops elevation by design.
    static func elevationProfile(_ coordinates: [RouteCoordinate], sampleCount: Int) -> [Double]? {
        let cumulative = cumulativeDistances(coordinates)
        let measured = zip(cumulative, coordinates).compactMap { distance, coordinate in
            coordinate.elevationMeters.map { (distance: distance, elevation: $0) }
        }
        guard measured.count > 1, let first = measured.first, let last = measured.last,
              let total = cumulative.last
        else { return nil }

        // One sample is not a profile, and the spacing below divides by `count - 1`.
        let count = max(sampleCount, 2)
        var samples: [Double] = []
        samples.reserveCapacity(count)
        var lower = 0
        for step in 0..<count {
            let distance = total * Double(step) / Double(count - 1)
            if distance <= first.distance {
                samples.append(first.elevation)
            } else if distance >= last.distance {
                samples.append(last.elevation)
            } else {
                // The two branches above leave `measured[lower].distance < distance`, and the loop
                // stops at the first point at or beyond it — so `span` is positive by construction.
                // Guarded anyway: a NaN here would surface in Swift Charts, not in a test.
                while measured[lower + 1].distance < distance { lower += 1 }
                let start = measured[lower]
                let end = measured[lower + 1]
                let span = end.distance - start.distance
                let t = span > 0 ? (distance - start.distance) / span : 1
                samples.append(start.elevation + (end.elevation - start.elevation) * t)
            }
        }
        return samples
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

// MARK: - Viewport intersection (#194)

extension RouteBounds {
    /// Whether two boxes overlap at all, edges included. Touching counts: a route whose
    /// easternmost point sits exactly on the viewport's western edge is drawn on that edge,
    /// so the list has to agree that it is visible.
    func intersects(_ other: RouteBounds) -> Bool {
        minLatitude <= other.maxLatitude && maxLatitude >= other.minLatitude
            && minLongitude <= other.maxLongitude && maxLongitude >= other.minLongitude
    }

    func contains(latitude: Double, longitude: Double) -> Bool {
        latitude >= minLatitude && latitude <= maxLatitude
            && longitude >= minLongitude && longitude <= maxLongitude
    }

    /// Whether this box holds all of `other`. S19 uses it to recognise a viewport that
    /// already shows every saved route, which is not a filter and must not raise the chip.
    func contains(_ other: RouteBounds) -> Bool {
        other.minLatitude >= minLatitude && other.maxLatitude <= maxLatitude
            && other.minLongitude >= minLongitude && other.maxLongitude <= maxLongitude
    }
}

extension RouteGeometry {

    /// Whether one drawn segment touches `box` — Liang–Barsky, clipping the segment's
    /// parameter against the four edges in turn and asking whether anything survives.
    ///
    /// **This is deliberately its own function rather than the body of `polyline`'s loop.**
    /// Written inline, its early `return false` would abandon the whole *route* on the first
    /// segment that falls outside, which is every zoomed-in case — and a fixture built from a
    /// route lying wholly inside the viewport can never catch it, because such a route never
    /// rejects a segment. `polylineWhoseFirstSegmentIsOutside` is the test that can.
    ///
    /// A zero-length segment leaves all four `p` at zero and reduces to point-in-box, which is
    /// the right answer: `GPXRouteImporter` does not dedupe consecutive identical points, so
    /// those do reach here.
    static func segment(
        from start: RouteCoordinate,
        to end: RouteCoordinate,
        intersects box: RouteBounds
    ) -> Bool {
        let dx = end.longitude - start.longitude
        let dy = end.latitude - start.latitude

        var t0 = 0.0
        var t1 = 1.0

        // `p` is how fast the segment crosses this edge, `q` how far inside it starts.
        // `p == 0` is a segment parallel to the edge, which survives only if it starts inside.
        func clip(_ p: Double, _ q: Double) -> Bool {
            guard p != 0 else { return q >= 0 }
            let r = q / p
            if p < 0 {
                if r > t1 { return false }
                if r > t0 { t0 = r }
            } else {
                if r < t0 { return false }
                if r < t1 { t1 = r }
            }
            return true
        }

        guard clip(-dx, start.longitude - box.minLongitude),
              clip(dx, box.maxLongitude - start.longitude),
              clip(-dy, start.latitude - box.minLatitude),
              clip(dy, box.maxLatitude - start.latitude)
        else { return false }

        return t0 <= t1
    }

    /// Whether any part of the drawn polyline touches `box`.
    ///
    /// Segment by segment, not vertex by vertex: a route that crosses the viewport with both
    /// of its endpoints — and every vertex — outside is still drawn across it, and UX.md §S19
    /// promises the list shows "those routes displayed on the map".
    ///
    /// No bounding-box pre-reject here, because the caller has a better one: `RouteSummary`
    /// already carries the route's stored bounds, so `RouteFilter` rejects in O(1) and only
    /// reaches this for the survivors. Recomputing the box here would walk the coordinates a
    /// second time for exactly those routes.
    ///
    /// Degrees rather than projected map points is right for this: the viewport and the stored
    /// bounds are both lat/lon, and over one route segment the difference between a straight
    /// line in degrees and the Mercator line MapKit actually draws is far below a metre.
    static func polyline(_ coordinates: [RouteCoordinate], intersects box: RouteBounds) -> Bool {
        guard let first = coordinates.first else { return false }
        // A one-point GPX imports fine — `GPXRouteImporter` rejects only *no* coordinates —
        // and has no segments to walk, so without this branch it could never match anything
        // while its marker sat in the middle of the viewport.
        guard coordinates.count > 1 else {
            return box.contains(latitude: first.latitude, longitude: first.longitude)
        }
        return zip(coordinates, coordinates.dropFirst())
            .contains { segment(from: $0, to: $1, intersects: box) }
    }
}
