import Testing
import CoreLocation
import MapKit
@testable import Cyclometer

/// S19's map camera (#193). These stand in for a snapshot of the map itself: a live
/// `MapKit` view renders tiles asynchronously and its first render per process differs
/// from later ones, so the pixels are not a stable reference — but the region it opens at
/// is ordinary arithmetic.
@Suite("RoutesMapCamera")
struct RoutesMapCameraTests {

    private static func bounds(
        _ minLat: Double, _ maxLat: Double, _ minLon: Double, _ maxLon: Double
    ) -> RouteBounds {
        RouteBounds(minLatitude: minLat, maxLatitude: maxLat,
                    minLongitude: minLon, maxLongitude: maxLon)
    }

    private static func route(_ bounds: RouteBounds) -> RouteSummary {
        var summary = RouteSummary.empty
        summary.id = UUID()
        summary.bounds = bounds
        return summary
    }

    /// A degree of latitude is ~111 km everywhere, so the 100-mile span the 50-mile radius
    /// implies is ~1.45° tall. Checked in degrees rather than by round-tripping through
    /// `MKCoordinateRegion`, which is what the view consumes.
    private static let expectedRiderSpanDegrees = (RoutesMapCamera.riderRadiusMeters * 2) / 111_320

    @Test("A rider fix centres the map on the rider at a 50-mile radius")
    func riderFixWins() {
        let rider = Coordinate(latitude: 44.9778, longitude: -93.2650)
        let region = RoutesMapCamera.region(
            riderCoordinate: rider,
            routes: [Self.route(Self.bounds(37.32, 37.35, -122.05, -122.00))]
        )

        #expect(abs(region.center.latitude - rider.latitude) < 0.0001)
        #expect(abs(region.center.longitude - rider.longitude) < 0.0001)
        // Generous: MKCoordinateRegion converts metres to degrees with its own projection.
        #expect(abs(region.span.latitudeDelta - Self.expectedRiderSpanDegrees) < 0.05)
    }

    /// The Routes tab opens without location permission ever having been granted, so this
    /// is a normal branch rather than an error path.
    @Test("With no rider fix, the region contains every route's bounds")
    func routeBoundsFallback() {
        let west = Self.bounds(37.29, 37.34, -122.14, -122.08)
        let east = Self.bounds(37.36, 37.38, -122.03, -121.98)
        let region = RoutesMapCamera.region(
            riderCoordinate: nil,
            routes: [Self.route(west), Self.route(east)]
        )

        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLon = region.center.longitude - region.span.longitudeDelta / 2
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2

        #expect(minLat <= west.minLatitude)
        #expect(maxLat >= east.maxLatitude)
        #expect(minLon <= west.minLongitude)
        #expect(maxLon >= east.maxLongitude)
    }

    @Test("No rider fix and no routes falls back to a fixed centre at the same span")
    func emptyFallback() {
        let region = RoutesMapCamera.region(riderCoordinate: nil, routes: [])

        #expect(region.center.latitude == RoutesMapCamera.fallbackCenter.latitude)
        #expect(region.center.longitude == RoutesMapCamera.fallbackCenter.longitude)
        #expect(abs(region.span.latitudeDelta - Self.expectedRiderSpanDegrees) < 0.05)
    }

    /// Without the floor this frames a zero-degree region and zooms to the pavement.
    @Test("A single-point route floors at the minimum span rather than collapsing")
    func degenerateBoundsFloor() {
        let point = Self.bounds(37.3349, 37.3349, -122.0090, -122.0090)
        let region = RoutesMapCamera.region(riderCoordinate: nil, routes: [Self.route(point)])

        #expect(region.span.latitudeDelta == RoutesMapCamera.minimumSpanDegrees)
        #expect(region.span.longitudeDelta == RoutesMapCamera.minimumSpanDegrees)
        #expect(abs(region.center.latitude - 37.3349) < 0.0001)
    }

    @Test("Union of an empty collection is nil")
    func emptyUnion() {
        #expect(RouteBounds.union([]) == nil)
    }

    @Test("Union takes the extreme of each edge")
    func unionExtremes() {
        let combined = RouteBounds.union([
            Self.bounds(10, 20, -5, 5),
            Self.bounds(15, 30, -20, 0)
        ])
        #expect(combined == Self.bounds(10, 30, -20, 5))
    }
}

// MARK: - Regressions from the #193 review

@Suite("RoutesMapCamera — span limits")
struct RoutesMapCameraSpanTests {

    private static func route(_ minLat: Double, _ maxLat: Double,
                              _ minLon: Double, _ maxLon: Double) -> RouteSummary {
        var summary = RouteSummary.empty
        summary.id = UUID()
        summary.bounds = RouteBounds(minLatitude: minLat, maxLatitude: maxLat,
                                     minLongitude: minLon, maxLongitude: maxLon)
        return summary
    }

    /// Two routes on opposite sides of the world span 297° of longitude, which the 1.6×
    /// padding pushes to 475°. `MKCoordinateSpan` only accepts 180/360, and MapKit answers an
    /// out-of-range region with an arbitrary camera rather than an error — so it has to be
    /// clamped here, where it is visible.
    @Test("A globe-spanning pair of routes is clamped to a valid region")
    func globalSpanIsClamped() {
        let region = RoutesMapCamera.region(
            riderCoordinate: nil,
            routes: [Self.route(37.30, 37.40, -122.10, -122.00),
                     Self.route(-41.30, -41.20, 174.70, 174.80)]
        )
        #expect(region.span.latitudeDelta <= 180)
        #expect(region.span.longitudeDelta <= 360)
    }

    /// `RouteBounds` documents the antimeridian as unhandled; what it must not do is produce
    /// a region MapKit rejects.
    @Test("A route straddling the antimeridian still yields a valid region")
    func antimeridianStillValid() {
        let region = RoutesMapCamera.region(
            riderCoordinate: nil,
            routes: [Self.route(-16.60, -16.50, -179.95, 179.95)]
        )
        #expect(region.span.longitudeDelta <= 360)
        #expect(region.span.latitudeDelta <= 180)
    }
}
