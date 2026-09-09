import Foundation
import SwiftData

/// A planned route imported from a `.gpx` file (DataModel.md schema v1.1, brought
/// forward into MVP by M8). Written once at import, read whole at ride start.
///
/// The polyline and the file's turn cues are JSON blobs in external storage rather than
/// child rows: nothing queries *inside* them, and the scalar columns above them are what
/// S19's list, its filters and S05.1's row actually read — so none of those screens pays
/// to decode a polyline that, for a route exported from a recorded ride, can run to tens
/// of thousands of points.
///
/// Elevation is deliberately **not** a third blob. `RouteCoordinate.elevationMeters`
/// already carries it per point, and a second copy could drift from the first.
///
/// Any non-optional attribute added here later needs a *declaration-site* default
/// (`= 0`, not just an `init` assignment): SwiftData takes the store-level default from
/// the declaration, and lightweight migration cannot backfill a mandatory attribute that
/// has none — it fails the whole store load and crashes at launch (#186, `Ride.swift:8`).
/// That rule does not bind the attributes below, because an entity arriving in the
/// schema for the first time has no existing rows to backfill.
@Model
final class Route {
    /// Used when the GPX names itself nowhere. `ImportedRoute.name` is a `var`, so an
    /// importing screen with a better fallback — the filename, say — sets it first.
    static let defaultName = "Imported Route"

    // MARK: - Identity
    var id: UUID
    var name: String
    /// S19's route row subtitle: the file's `<desc>`, falling back to `<type>`.
    var terrainDescription: String?
    var importedAt: Date

    // MARK: - Derived at import (RouteGeometry)
    var distanceMeters: Double
    var coordinateCount: Int
    /// Nil when the source GPX carried no `<ele>` at all — distinct from `0`, which is a
    /// genuinely flat route. S20 hides its whole elevation section on nil (#195).
    var elevationGainMeters: Double?
    var elevationLossMeters: Double?

    // MARK: - Bounding box
    // Flat columns rather than a nested value so a #Predicate can filter on them:
    // #194's map-as-filter has to narrow routes to a viewport without loading polylines.
    var minLatitude: Double
    var maxLatitude: Double
    var minLongitude: Double
    var maxLongitude: Double

    // MARK: - Geometry (external storage)
    @Attribute(.externalStorage)
    var polylineData: Data?

    var coordinates: [RouteCoordinate] {
        get { polylineData.flatMap { try? JSONDecoder().decode([RouteCoordinate].self, from: $0) } ?? [] }
        set { polylineData = try? JSONEncoder().encode(newValue) }
    }

    @Attribute(.externalStorage)
    var cuePointsData: Data?

    var cuePoints: [RouteCuePoint] {
        get { cuePointsData.flatMap { try? JSONDecoder().decode([RouteCuePoint].self, from: $0) } ?? [] }
        set { cuePointsData = try? JSONEncoder().encode(newValue) }
    }

    /// The only way a `Route` is made: from a parsed file, deriving distance, elevation
    /// and bounds once. Everything derived is stored rather than recomputed on read,
    /// because S19 sorts and filters on it.
    init(imported: ImportedRoute, id: UUID = UUID(), importedAt: Date = .now) {
        let bounds = RouteGeometry.boundingBox(imported.coordinates)
        let elevation = RouteGeometry.elevationGainLoss(imported.coordinates)

        self.id = id
        self.name = imported.name ?? Self.defaultName
        self.terrainDescription = imported.terrainDescription
        self.importedAt = importedAt

        self.distanceMeters = RouteGeometry.distanceMeters(imported.coordinates)
        self.coordinateCount = imported.coordinates.count
        self.elevationGainMeters = elevation?.gain
        self.elevationLossMeters = elevation?.loss

        self.minLatitude = bounds.minLatitude
        self.maxLatitude = bounds.maxLatitude
        self.minLongitude = bounds.minLongitude
        self.maxLongitude = bounds.maxLongitude

        // The stored blobs directly, not the computed accessors above: those are
        // unavailable until every stored property is initialised.
        self.polylineData = try? JSONEncoder().encode(imported.coordinates)
        self.cuePointsData = try? JSONEncoder().encode(imported.cuePoints)
    }
}

extension Route {
    /// This route without its geometry — everything S19's list, its filter sheet and
    /// S05.1's row need, and nothing that costs a blob decode.
    var summary: RouteSummary {
        RouteSummary(
            id: id,
            name: name,
            terrainDescription: terrainDescription,
            importedAt: importedAt,
            distanceMeters: distanceMeters,
            coordinateCount: coordinateCount,
            elevationGainMeters: elevationGainMeters,
            elevationLossMeters: elevationLossMeters,
            bounds: RouteBounds(
                minLatitude: minLatitude,
                maxLatitude: maxLatitude,
                minLongitude: minLongitude,
                maxLongitude: maxLongitude
            )
        )
    }

    /// The whole route, geometry included — S20 and ride start.
    var detail: RouteDetail {
        RouteDetail(summary: summary, coordinates: coordinates, cuePoints: cuePoints)
    }

    /// What a `Ride` denormalizes at start.
    var reference: RouteReference {
        RouteReference(id: id, name: name)
    }
}

// MARK: - Boundary types
//
// `@Model` classes aren't `Sendable` (see `VehiclePassEvent.swift:39-41`), so these are
// what actually cross `PersistenceClient`'s `@Sendable` closures.

/// A route without its polyline. The split exists because the list, the filters and the
/// active-route row are read far more often than a route is opened, and decoding a
/// polyline for each of them would be the expensive half of every one of those reads.
struct RouteSummary: Sendable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var terrainDescription: String?
    var importedAt: Date
    var distanceMeters: Double
    var coordinateCount: Int
    var elevationGainMeters: Double?
    var elevationLossMeters: Double?
    var bounds: RouteBounds
}

extension RouteSummary {
    /// The inert value `PersistenceClient.testValue` hands back, matching how its
    /// `fetchRide` returns a blank `RideExportMetadata`: a test that has not overridden
    /// the dependency should get something obviously empty and deterministic, never a
    /// fresh `UUID()` that makes an assertion unwritable.
    static let empty = RouteSummary(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
        name: "",
        terrainDescription: nil,
        importedAt: Date(timeIntervalSince1970: 0),
        distanceMeters: 0,
        coordinateCount: 0,
        elevationGainMeters: nil,
        elevationLossMeters: nil,
        bounds: RouteBounds(minLatitude: 0, maxLatitude: 0, minLongitude: 0, maxLongitude: 0)
    )
}

/// A route with its polyline and the file's turn cues. #192 derives maneuvers from these
/// two at route *load*; they are never persisted, so a later fix to the derivation can't
/// leave old routes on stale output.
struct RouteDetail: Sendable, Equatable {
    var summary: RouteSummary
    var coordinates: [RouteCoordinate]
    var cuePoints: [RouteCuePoint]
}

/// The (id, name) pair a `Ride` denormalizes when it starts. One value rather than two
/// parameters, so a ride can't be written with an id and a mismatched name.
struct RouteReference: Sendable, Equatable {
    var id: UUID
    var name: String
}
