import CoreLocation
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

    /// Geodesic length of the polyline.
    ///
    /// `CLLocation.distance(from:)` rather than a hand-rolled haversine: it is the
    /// reference implementation, and its per-point allocation is a one-time import cost
    /// bounded by `GPXRouteImporter.maximumCoordinateCount`.
    static func distanceMeters(_ coordinates: [RouteCoordinate]) -> Double {
        guard let first = coordinates.first else { return 0 }
        var total = 0.0
        var previous = CLLocation(latitude: first.latitude, longitude: first.longitude)
        for coordinate in coordinates.dropFirst() {
            let current = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            total += current.distance(from: previous)
            previous = current
        }
        return total
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
