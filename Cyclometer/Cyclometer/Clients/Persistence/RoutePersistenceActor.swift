import Foundation
import SwiftData
import os

// Stream live: Console.app / Xcode console, filter subsystem "com.xavier.cyclometer".
private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "persistence")

/// Serializes every SwiftData `Route` access behind one long-lived ModelContext, the way
/// `RidePersistenceActor` does for rides.
///
/// A second actor rather than more methods on that one, because the two own disjoint
/// tables and neither reads the other's: this touches only `Route`, `RidePersistenceActor`
/// only `Ride` and `VehiclePassEvent`. Keeping them apart means there is no cross-context
/// staleness to reason about, and a route import — user-initiated and rare — never queues
/// behind the 30-second ride checkpoint, which runs for the whole duration of every ride.
/// The one place a ride needs route data, `createRide`, is handed a `RouteReference`
/// rather than resolving an id against this table, which is what keeps that true.
@ModelActor
actor RoutePersistenceActor {

    /// Persists a parsed file. Returns the stored summary because the importing screen
    /// needs the new id to select or navigate to what it just imported.
    ///
    /// No de-duplication, deliberately: importing the same `.gpx` twice yields two rows.
    /// A rider may well import a deliberate variant of a route they already have, and
    /// there is no identity in a GPX file to key on that would tell the two apart. If
    /// duplicates turn out to be a nuisance in practice, the decision belongs in S19's
    /// import flow (#193), which is the only place that knows the file it came from.
    func importRoute(_ imported: ImportedRoute) throws -> RouteSummary {
        let route = Route(imported: imported)
        try savingChanges("importRoute", id: route.id, context: modelContext) {
            modelContext.insert(route)
        }
        return route.summary
    }

    /// Newest first, matching the rides list. Scalar columns only — `RouteSummary` carries
    /// no geometry, so this never decodes a polyline blob.
    func fetchRoutes() throws -> [RouteSummary] {
        do {
            let descriptor = FetchDescriptor<Route>(
                sortBy: [SortDescriptor(\.importedAt, order: .reverse)]
            )
            return try modelContext.fetch(descriptor).map(\.summary)
        } catch {
            logger.error("fetchRoutes failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// The whole route, geometry decoded. `nil` rather than a thrown `.routeNotFound`,
    /// deliberately: unlike a ride id — which the app minted moments earlier and must
    /// therefore exist — a route id can be a dangling FK *by design*, because deleting a
    /// route leaves `Ride.routeId` pointing at nothing. Absence is an expected outcome
    /// here, not an error.
    func fetchRoute(id: UUID) throws -> RouteDetail? {
        try routeRow(id: id)?.detail
    }

    /// No-op when the route is already gone — deleting something twice is not a failure,
    /// and S19's swipe-to-delete can race its own list refresh.
    ///
    /// Rides that referenced this route keep their `routeId` and their `routeName`. The
    /// id is left dangling on purpose: `routeName` is the historical record of what the
    /// ride was, and clearing either would rewrite history to tidy up a foreign key.
    func deleteRoute(id: UUID) throws {
        guard let route = try routeRow(id: id) else { return }
        try savingChanges("deleteRoute", id: id, context: modelContext) {
            modelContext.delete(route)
        }
    }

    /// Stores a route's OpenStreetMap surface (#252), the one attribute written after import.
    /// No-op when the route was deleted while the lookup was in flight.
    func saveRouteSurface(id: UUID, surface: RouteSurfaceBreakdown) throws {
        guard let route = try routeRow(id: id) else { return }
        let data = try JSONEncoder().encode(surface)
        try savingChanges("saveRouteSurface", id: id, context: modelContext) {
            route.surfaceData = data
        }
    }

    /// S19's map thumbnail, both appearances in one save (#273). A write of its own rather than
    /// part of `importRoute`, for the reason `RidePersistenceActor.saveMapThumbnail` gives: the
    /// render needs map tiles, and the import must not wait on them. No-op when the route was
    /// deleted while it rendered, like `saveRouteSurface`.
    func saveMapThumbnail(id: UUID, light: Data, dark: Data) throws {
        guard let route = try routeRow(id: id) else { return }
        try savingChanges("saveRouteMapThumbnail", id: id, context: modelContext) {
            route.mapThumbnailLight = light
            route.mapThumbnailDark = dark
        }
    }

    /// Routes still without a map thumbnail, newest first (#273) — what
    /// `RouteMapThumbnail.backfill` works through.
    func routeIdsMissingMapThumbnail() throws -> [UUID] {
        do {
            let descriptor = FetchDescriptor<Route>(
                predicate: #Predicate { $0.mapThumbnailLight == nil },
                sortBy: [SortDescriptor(\.importedAt, order: .reverse)]
            )
            return try modelContext.fetch(descriptor).map(\.id)
        } catch {
            logger.error("routeIdsMissingMapThumbnail failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// One route's stored thumbnail (#273). Nil for a route without one, and for an unknown id,
    /// which a row outliving its route's delete can ask about.
    func fetchMapThumbnail(id: UUID) throws -> RideMapThumbnailData? {
        do {
            guard let route = try routeRow(id: id),
                  let light = route.mapThumbnailLight, let dark = route.mapThumbnailDark
            else { return nil }
            return RideMapThumbnailData(light: light, dark: dark)
        } catch {
            logger.error("fetchMapThumbnail(\(id, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Derives terrain for routes imported before #252, whose polylines were stored but never
    /// analysed. Returns how many it filled in, so the caller re-reads only when that is not 0.
    ///
    /// Only routes with elevation qualify, so a route without `<ele>` is never decoded here. One
    /// with elevation can still analyse to nil — a polyline that no longer decodes, or one with
    /// no length — and that route is marked with an empty `terrainData`, which reads back as no
    /// analysis but keeps it out of this predicate. Left nil, it would be decoded and
    /// re-analysed to nil on every visit to the Routes tab, forever.
    func backfillRouteTerrain() throws -> Int {
        let descriptor = FetchDescriptor<Route>(
            predicate: #Predicate { $0.terrainData == nil && $0.elevationGainMeters != nil }
        )
        do {
            var filled = 0
            for route in try modelContext.fetch(descriptor) {
                route.terrainData = try RouteTerrain.analyze(route.coordinates).map { try JSONEncoder().encode($0) }
                    ?? Data()
                filled += 1
            }
            guard filled > 0 else { return 0 }
            try modelContext.save()
            logger.notice("backfilled terrain on \(filled, privacy: .public) routes")
            return filled
        } catch {
            logger.error("backfillRouteTerrain failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// The row itself, for the callers that need the object rather than a DTO.
    /// Named apart from `fetchRoute(id:)` on purpose — overloading on return type alone
    /// would make every call site's meaning depend on inference.
    private func routeRow(id: UUID) throws -> Route? {
        var descriptor = FetchDescriptor<Route>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
