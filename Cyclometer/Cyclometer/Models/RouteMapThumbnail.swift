import ComposableArchitecture
import Foundation
import os
import UIKit

// Stream live: Console.app / Xcode console, filter subsystem "com.xavier.cyclometer".
private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "routes")

/// S19's row thumbnail (#273): the route's polyline in `cyMapRoute` over a static map, the same
/// image S14 shows for a ride. Framing, path and size are `RideMapThumbnail`'s, so a route and
/// a ride over the same roads are drawn alike; only where the line comes from, its colour and
/// where the images are stored differ.
enum RouteMapThumbnail {
    /// The polyline as one segment — a route has no pauses to split at. Empty when it has
    /// fewer than two points, which draw nothing.
    static func drawableSegments(_ coordinates: [RouteCoordinate]) -> [[RouteCoordinate]] {
        coordinates.count > 1 ? [coordinates] : []
    }

    /// One route's stored image, decoded for both appearances — what S19's and S05.2's rows
    /// read as they appear. Nil for none yet, or a failed read (logged inside
    /// `RoutePersistenceActor`).
    static func images(_ routeId: UUID, from persistenceClient: PersistenceClient) async -> RideThumbnailImages? {
        guard let data = try? await persistenceClient.fetchRouteMapThumbnail(routeId) else { return nil }
        return await RideThumbnailImages.decode(data)
    }

    /// Renders the thumbnail of every route that lacks one, newest first, and returns how many
    /// it stored. Runs after an import, where the newest route is the one just imported, and at
    /// launch and on each visit to S19, which catch routes imported before #273 and any failed
    /// render.
    ///
    /// The first failed render ends the batch, and a route with nothing to draw is skipped and
    /// looked at again next time — both for the reasons `RideMapThumbnail.backfill` gives.
    /// Through the same gate as rides, so an import never renders alongside a ride backfill
    /// still waiting on the network.
    @discardableResult
    static func backfill() async -> Int {
        @Dependency(\.mapThumbnailGate) var gate
        return await gate.run { await backfillNow() }
    }

    private static func backfillNow() async -> Int {
        @Dependency(\.persistenceClient) var persistenceClient
        let routeIds: [UUID]
        do {
            routeIds = try await persistenceClient.fetchRouteIdsMissingMapThumbnail()
        } catch {
            return 0 // Logged inside RoutePersistenceActor.
        }
        var stored = 0
        for routeId in routeIds {
            do {
                if try await capture(routeId: routeId) { stored += 1 }
            } catch {
                logger.error("Map thumbnail capture failed for route \(routeId, privacy: .public): \(error.localizedDescription, privacy: .public) — retried next visit")
                break
            }
        }
        return stored
    }

    /// Renders both appearances from one route's stored polyline and stores them on the route.
    /// Returns false, having stored nothing, for a route that is gone or has nothing to draw.
    @discardableResult
    static func capture(routeId: UUID) async throws -> Bool {
        @Dependency(\.persistenceClient) var persistenceClient
        @Dependency(\.mapSnapshotClient) var mapSnapshotClient
        guard let route = try await persistenceClient.fetchRoute(routeId) else { return false }
        let segments = drawableSegments(route.coordinates)
        guard !segments.isEmpty else { return false }
        let mapRect = RideMapThumbnail.mapRect(for: segments)
        async let light = mapSnapshotClient.render(mapRect, segments, .cyMapRoute, .light)
        async let dark = mapSnapshotClient.render(mapRect, segments, .cyMapRoute, .dark)
        try await persistenceClient.saveRouteMapThumbnail(routeId, light, dark)
        return true
    }
}
