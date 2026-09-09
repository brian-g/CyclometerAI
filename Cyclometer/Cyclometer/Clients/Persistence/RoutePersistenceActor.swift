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
    func importRoute(_ imported: ImportedRoute) throws -> RouteSummary {
        let route = Route(imported: imported)
        try savingChanges("importRoute", id: route.id) {
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
        try savingChanges("deleteRoute", id: id) {
            modelContext.delete(route)
        }
    }

    /// The row itself, for the two callers that need the object rather than a DTO.
    /// Named apart from `fetchRoute(id:)` on purpose — overloading on return type alone
    /// would make every call site's meaning depend on inference.
    private func routeRow(id: UUID) throws -> Route? {
        var descriptor = FetchDescriptor<Route>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Shared body for every write: run `changes` (insert/delete/mutate, no save), save
    /// the context, and log-then-rethrow under one label on failure. Mirrors
    /// `RidePersistenceActor.savingChanges`.
    private func savingChanges(_ label: String, id: UUID, _ changes: () throws -> Void) throws {
        do {
            try changes()
            try modelContext.save()
        } catch {
            logger.error("\(label, privacy: .public)(\(id, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}
