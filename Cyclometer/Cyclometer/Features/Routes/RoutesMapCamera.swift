import CoreLocation
import MapKit

/// Where S19's route map opens.
///
/// A free function over values rather than `@State` inside the map view, because the
/// decision has three branches and a live `MapKit` view cannot be pixel-snapshot-tested
/// reliably — tiles render asynchronously and the first render per process differs from
/// later ones. Pulled out here, the choice is ordinary arithmetic with ordinary tests.
enum RoutesMapCamera {

    /// UX.md §S19: "Map will initially zoom to a 50 mile radius around the user's current
    /// location." A radius, so the region spans twice this.
    static let riderRadiusMeters: CLLocationDistance = 50 * 1609.344

    /// Apple Park. Only ever seen by a rider with no location permission and no saved
    /// routes — an empty map has to open somewhere, and somewhere on land beats (0, 0).
    static let fallbackCenter = CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090)

    /// Padding around the routes' own extent, so the polylines don't touch the edges.
    static let boundsPadding = 1.6

    /// Floor on a bounds-derived span. A one-point route, or several routes starting from
    /// the same street, would otherwise frame a zero-degree region and zoom to the pavement.
    static let minimumSpanDegrees = 0.015

    /// Rider's position if we have one, else every saved route's combined extent, else
    /// `fallbackCenter`. The Routes tab is reachable without location permission ever
    /// having been granted, so the second and third branches are normal, not error paths.
    static func region(riderCoordinate: Coordinate?, routes: [RouteSummary]) -> MKCoordinateRegion {
        if let riderCoordinate {
            return riderRegion(centeredOn: riderCoordinate.clLocationCoordinate2D)
        }
        guard let bounds = RouteBounds.union(routes.map(\.bounds)) else {
            return riderRegion(centeredOn: fallbackCenter)
        }
        let center = bounds.center
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
            span: MKCoordinateSpan(
                latitudeDelta: span((bounds.maxLatitude - bounds.minLatitude), limit: 180),
                longitudeDelta: span((bounds.maxLongitude - bounds.minLongitude), limit: 360)
            )
        )
    }

    /// Padded, floored, and clamped to what `MKCoordinateSpan` actually accepts. The clamp is
    /// not theoretical: routes on opposite sides of the world — or one route crossing ±180,
    /// which `RouteBounds` documents as unhandled — produce a padded delta well over 360, and
    /// MapKit answers an out-of-range region with an arbitrary camera rather than an error.
    private static func span(_ extent: Double, limit: Double) -> Double {
        min(max(extent * boundsPadding, minimumSpanDegrees), limit)
    }

    private static func riderRegion(centeredOn center: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: center,
            latitudinalMeters: riderRadiusMeters * 2,
            longitudinalMeters: riderRadiusMeters * 2
        )
    }
}

// MARK: - Viewport capture (#194)

extension RoutesMapCamera {

    /// The exact camera region, restored rather than re-framed — no padding and no minimum
    /// span, because this is the viewport the rider left the map on, not a box being fitted
    /// around content.
    static func region(for bounds: RouteBounds) -> MKCoordinateRegion {
        let center = bounds.center
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
            span: MKCoordinateSpan(
                latitudeDelta: min(max(bounds.maxLatitude - bounds.minLatitude, .leastNormalMagnitude), 180),
                longitudeDelta: min(max(bounds.maxLongitude - bounds.minLongitude, .leastNormalMagnitude), 360)
            )
        )
    }

    /// The box a camera region covers. Nil only for a region MapKit reports as non-finite,
    /// which it does for a camera that has not settled.
    ///
    /// **Clamped, never wrapped.** `center ± span/2` runs past ±90 and ±180 on a zoomed-out
    /// camera, and wrapping the two longitudes back into range independently *inverts* the box
    /// — `minLongitude` ends up greater than `maxLongitude`, and `intersects` then rejects
    /// every route, emptying the list at world zoom. Same stance as `span(_:limit:)` above,
    /// which clamps rather than trusting what MapKit hands back.
    static func bounds(for region: MKCoordinateRegion) -> RouteBounds? {
        let center = region.center
        let latitudeDelta = region.span.latitudeDelta
        let longitudeDelta = region.span.longitudeDelta
        // A zero span is a camera mid-transition, not a viewport. Restoring one hands MapKit an
        // effectively zero `MKCoordinateSpan` — street level on an arbitrary point — and as a
        // filter it is a zero-area box that intersects almost nothing, emptying the list behind
        // a chip that explains none of it.
        guard center.latitude.isFinite, center.longitude.isFinite,
              latitudeDelta.isFinite, longitudeDelta.isFinite,
              latitudeDelta > 0, longitudeDelta > 0
        else { return nil }

        // A camera showing a full turn of longitude has no west or east edge to speak of;
        // `center ± 180` would describe a box that excludes the antimeridian instead.
        let longitudes: (min: Double, max: Double) = longitudeDelta >= 360
            ? (-180, 180)
            : (max(center.longitude - longitudeDelta / 2, -180),
               min(center.longitude + longitudeDelta / 2, 180))

        let bounds = RouteBounds(
            minLatitude: max(center.latitude - latitudeDelta / 2, -90),
            maxLatitude: min(center.latitude + latitudeDelta / 2, 90),
            minLongitude: longitudes.min,
            maxLongitude: longitudes.max
        )
        // The clamps above hold the box the right way round for a centre that is itself in
        // range. A centre that is not — which MapKit can report after panning across the
        // antimeridian — clamps to an *inverted* box, and `intersects` would then reject every
        // route. Refusing the region keeps the invariant this function documents.
        guard bounds.minLatitude <= bounds.maxLatitude,
              bounds.minLongitude <= bounds.maxLongitude
        else { return nil }
        return bounds
    }

    /// The same box, but nil when it already holds every saved route — a viewport that excludes
    /// nothing is not a filter.
    ///
    /// Separate from `bounds(for:)` because the two answers are wanted in different places: the
    /// *filter* should be absent at a zoom that shows everything, while the direction chevrons
    /// still need to know what is on screen in order to space themselves. Collapsing the two
    /// would leave a library spread across two continents with a chip on screen from the moment
    /// the map opened, explaining an exclusion that was not happening.
    static func filterBounds(
        for region: MKCoordinateRegion,
        routes: [RouteSummary]
    ) -> RouteBounds? {
        guard let bounds = bounds(for: region) else { return nil }
        if let all = RouteBounds.union(routes.map(\.bounds)), bounds.contains(all) { return nil }
        return bounds
    }
}
