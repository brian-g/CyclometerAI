import Foundation

/// A planned route as it comes out of a `.gpx` file — the product of
/// `GPXRouteImporter`, before anything is persisted or derived from it.
///
/// Deliberately carries no distance, elevation gain/loss or point count: those are
/// arithmetic over `coordinates`, and belong with the `Route` @Model that stores them
/// (#191), not with the parser that read the file.
struct ImportedRoute: Equatable, Sendable {
    /// `<trk>`/`<rte>` `<name>`, falling back to `<metadata><name>`. Nil when the file
    /// names itself nowhere — the importing screen supplies a placeholder.
    var name: String?
    /// Free text for S19's route row subtitle: `<desc>` where the file has one,
    /// otherwise `<type>` (typically `cycling`).
    var terrainDescription: String?
    /// The polyline, in ride order. Never empty — an empty file is `.noCoordinates`.
    var coordinates: [RouteCoordinate]
    /// Turn cues as the file states them, in document order. Empty for a bare track,
    /// which is why #192's derivation has a geometric fallback.
    var cuePoints: [RouteCuePoint]
}

/// One point on a route's polyline.
///
/// `Codable` because #191 persists the polyline as an `@Attribute(.externalStorage)`
/// blob behind a computed accessor. Elevation is optional *per point* because that is
/// what the format allows; a planned route commonly has no `<ele>` at all, which is how
/// a stored route ends up with nil elevation gain rather than a misleading zero.
struct RouteCoordinate: Equatable, Sendable, Codable {
    var latitude: Double
    var longitude: Double
    var elevationMeters: Double?
}

/// A turn cue as the source file stated it — not yet a maneuver. #192 turns these into
/// `Maneuver`s, resolving direction from `type`/`name` or from polyline geometry.
struct RouteCuePoint: Equatable, Sendable, Codable {
    var latitude: Double
    var longitude: Double
    /// e.g. "Turn left onto County Road S".
    var name: String?
    var cueDescription: String?
    /// RideWithGPS states the turn here ("Left", "Right"); Komoot usually leaves it nil
    /// and puts the instruction in `name`.
    var type: String?
}
