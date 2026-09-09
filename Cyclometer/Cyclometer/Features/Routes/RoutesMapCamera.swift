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
