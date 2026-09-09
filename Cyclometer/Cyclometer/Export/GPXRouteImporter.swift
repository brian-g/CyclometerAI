import Foundation

/// Reads a planned route out of a `.gpx` file (PRD §8.6; OQ12 resolved navigation to
/// GPX import only, so an imported file is the *only* source of a route).
///
/// The files come from Komoot, RideWithGPS, Strava and OnTheGoMap, which disagree about
/// shape: some write a `<trk>` of `<trkpt>`, some a `<rte>` of `<rtept>`, some hang turn
/// cues off standalone `<wpt>`s, and a planned route usually carries neither `<ele>` nor
/// `<time>`. This resolves those into one route; `GPXParsing` does the XML.
///
/// A plain namespace of static functions, matching `GPXExporter` on the write side —
/// parsing is not a dependency, so this is not a client.
enum GPXRouteImporter {
    /// Generous next to a real route file (a 200 km ride at 1 Hz is a few hundred KB),
    /// tight enough that a mis-picked video cannot be read into memory.
    static let maximumFileSizeBytes = 16 * 1024 * 1024
    /// ~8× the points in a very long recorded ride, and far more than any planned route.
    static let maximumCoordinateCount = 100_000

    /// Reads and parses a file. The caps are parameters, not just constants, so tests can
    /// trip them without a 16 MB fixture — the same reason `GPXExporter.write` takes its
    /// `documentsDirectory`.
    ///
    /// Does *not* take a security-scoped resource: the `fileImporter` that vends the URL
    /// owns that lifetime (#193), and it has to span more than this call.
    static func route(
        contentsOf url: URL,
        maximumFileSizeBytes: Int = GPXRouteImporter.maximumFileSizeBytes,
        maximumCoordinateCount: Int = GPXRouteImporter.maximumCoordinateCount
    ) throws -> ImportedRoute {
        // Checked from the file's metadata first so an oversized file is refused before
        // it is read at all. A URL that won't report a size isn't rejected on that
        // basis — the count check below still catches it.
        if let declaredSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           declaredSize > maximumFileSizeBytes {
            throw GPXImportError.fileTooLarge
        }

        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw GPXImportError.unreadableFile
        }
        guard data.count <= maximumFileSizeBytes else { throw GPXImportError.fileTooLarge }

        return try route(from: data, maximumCoordinateCount: maximumCoordinateCount)
    }

    /// Pure — no I/O, no dependencies — so the shape rules can be exercised directly
    /// against fixtures, the same way `GPXExporter.buildXML` is.
    static func route(
        from data: Data,
        maximumCoordinateCount: Int = GPXRouteImporter.maximumCoordinateCount
    ) throws -> ImportedRoute {
        try route(from: GPXParsing.parse(data, maximumPointCount: maximumCoordinateCount))
    }

    static func route(from parsed: ParsedGPX) throws -> ImportedRoute {
        // A file carrying both gets its geometry from the track: <trk> is a recorded or
        // densely-sampled path, <rte> is a sparse list of waypoints between them.
        let usesTrack = !parsed.trackPoints.isEmpty

        let coordinates: [RouteCoordinate] = usesTrack
            ? parsed.trackPoints.compactMap { coordinate($0.latitude, $0.longitude, $0.elevation) }
            : parsed.routePoints.compactMap { coordinate($0.latitude, $0.longitude, $0.elevation) }
        guard !coordinates.isEmpty else { throw GPXImportError.noCoordinates }

        // Cues come from both containers regardless of which won the geometry: a
        // RideWithGPS file states them as <wpt>, a Komoot <rte> as named <rtept>.
        let cuePoints = parsed.waypoints.compactMap(cue(fromWaypoint:))
            + parsed.routePoints.compactMap(cue(fromRoutePoint:))

        // The container that supplied the geometry describes it; the other is a fallback
        // for the odd file that names only the one it didn't use.
        let ownName = usesTrack ? parsed.trackName : parsed.routeName
        let otherName = usesTrack ? parsed.routeName : parsed.trackName
        let ownDescription = usesTrack ? parsed.trackDescription : parsed.routeDescription
        let otherDescription = usesTrack ? parsed.routeDescription : parsed.trackDescription
        let type = usesTrack ? parsed.trackType ?? parsed.routeType : parsed.routeType ?? parsed.trackType

        return ImportedRoute(
            name: ownName ?? otherName ?? parsed.metadataName,
            // <type> last: "cycling" is a poor subtitle, but a better one than nothing.
            terrainDescription: ownDescription ?? otherDescription ?? parsed.metadataDescription ?? type,
            coordinates: coordinates,
            cuePoints: cuePoints
        )
    }

    // MARK: - Element mapping

    /// `<type>` on a `<wpt>` Cyclometer wrote itself. Re-importing one of your own
    /// exported rides as a route must not plant a turn cue at every car that passed you.
    private static let vehiclePassWaypointType = "vehiclePass"

    /// A point missing or malforming either coordinate is dropped rather than failing the
    /// import: one bad element in a thousand shouldn't cost the rider the route. Dropping
    /// *all* of them still surfaces as `.noCoordinates`.
    ///
    /// "Malformed" has to include non-finite, not just absent. `Double.init` accepts
    /// `"nan"` and turns `"1e999"` into `.infinity`, and either one poisons everything
    /// downstream: `Swift.min(.nan, x)` is `.nan`, so a single bad point makes NaN of a
    /// whole route's stored bounding box and distance, and `JSONEncoder` *throws* on a
    /// non-conforming float, which would leave the polyline blob nil while
    /// `coordinateCount` still claimed thousands of points. A range check comes with it:
    /// a latitude of 200 is not a coordinate either, and costs nothing to reject here.
    private static func coordinate(
        _ latitude: Double?, _ longitude: Double?, _ elevation: Double?
    ) -> RouteCoordinate? {
        guard let latitude, let longitude, isValid(latitude, longitude) else { return nil }
        // A non-finite `<ele>` drops the elevation, not the point — the coordinate is
        // still good, and elevation is optional per point by design.
        let elevationMeters = elevation.flatMap { $0.isFinite ? $0 : nil }
        return RouteCoordinate(latitude: latitude, longitude: longitude, elevationMeters: elevationMeters)
    }

    private static func isValid(_ latitude: Double, _ longitude: Double) -> Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }

    private static func cue(fromWaypoint waypoint: ParsedGPX.Waypoint) -> RouteCuePoint? {
        guard let latitude = waypoint.latitude, let longitude = waypoint.longitude,
              isValid(latitude, longitude) else { return nil }
        guard waypoint.type != vehiclePassWaypointType else { return nil }
        return RouteCuePoint(
            latitude: latitude, longitude: longitude,
            name: waypoint.name, cueDescription: waypoint.desc, type: waypoint.type
        )
    }

    /// Only *named* route points are cues. Komoot writes every vertex as an `<rtept>` and
    /// names the ones that are turns; treating all of them as cues would make a cue of
    /// every bend in the road.
    private static func cue(fromRoutePoint point: ParsedGPX.RoutePoint) -> RouteCuePoint? {
        guard let latitude = point.latitude, let longitude = point.longitude,
              isValid(latitude, longitude) else { return nil }
        guard point.name?.isEmpty == false || point.desc?.isEmpty == false else { return nil }
        return RouteCuePoint(
            latitude: latitude, longitude: longitude,
            name: point.name, cueDescription: point.desc, type: point.type
        )
    }
}
