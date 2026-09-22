import Foundation
import SwiftData
import Testing
@testable import Cyclometer

/// `Route` exactly as it stood before #252 added `terrainData` and `surfaceData`. A real
/// `@Model` for the same reason as `RideSchemaBeforeSampleCounts`: SwiftData derives the entity
/// name from the class name, so this writes a store whose `Route` table matches what that build
/// wrote. `Ride` and `VehiclePassEvent` are the shipping models; neither changed.
private enum RouteSchemaBeforeAnalysis {
    @Model
    final class Route {
        var id: UUID
        var name: String
        var terrainDescription: String?
        var importedAt: Date
        var distanceMeters: Double
        var coordinateCount: Int
        var elevationGainMeters: Double?
        var elevationLossMeters: Double?
        var minLatitude: Double
        var maxLatitude: Double
        var minLongitude: Double
        var maxLongitude: Double
        @Attribute(.externalStorage)
        var polylineData: Data?
        @Attribute(.externalStorage)
        var cuePointsData: Data?

        /// Built from the shipping derivation, so the legacy row holds what that build would
        /// have stored for the same file.
        init(imported: ImportedRoute) {
            let summary = RouteSummary(imported: imported)
            id = summary.id
            name = summary.name
            terrainDescription = summary.terrainDescription
            importedAt = summary.importedAt
            distanceMeters = summary.distanceMeters
            coordinateCount = summary.coordinateCount
            elevationGainMeters = summary.elevationGainMeters
            elevationLossMeters = summary.elevationLossMeters
            minLatitude = summary.bounds.minLatitude
            maxLatitude = summary.bounds.maxLatitude
            minLongitude = summary.bounds.minLongitude
            maxLongitude = summary.bounds.maxLongitude
            polylineData = try? JSONEncoder().encode(imported.coordinates)
            cuePointsData = try? JSONEncoder().encode(imported.cuePoints)
        }
    }

    static let schema = Schema([Ride.self, VehiclePassEvent.self, Self.Route.self])
}

@Suite("Route schema migration")
struct RouteSchemaMigrationTests {

    /// 3 km at 6%, then level: one Cat 3 climb (score 18,000) once analysed.
    private static let hilly = ImportedRoute(
        name: "Pilot Mountain",
        terrainDescription: nil,
        coordinates: RouteFixtures.path(legs: [(0, 4_000)], spacingMeters: 10).enumerated().map { index, point in
            var point = point
            point.elevationMeters = 300 + min(Double(index) * 10, 3_000) * 0.06
            return point
        },
        cuePoints: []
    )

    /// Elevation, so gain is stored, but every point in one place: no length, so no analysis.
    private static let stationary = ImportedRoute(
        name: "Trainer",
        terrainDescription: nil,
        coordinates: [RouteCoordinate(latitude: 36, longitude: -80, elevationMeters: 100),
                      RouteCoordinate(latitude: 36, longitude: -80, elevationMeters: 110)],
        cuePoints: []
    )

    private func writeLegacyStore(at url: URL) throws {
        let schema = RouteSchemaBeforeAnalysis.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let context = ModelContext(container)
        context.insert(RouteSchemaBeforeAnalysis.Route(imported: Self.hilly))
        context.insert(RouteSchemaBeforeAnalysis.Route(imported: RoutePersistenceTests.flatlandTrackWithoutElevation()))
        context.insert(RouteSchemaBeforeAnalysis.Route(imported: Self.stationary))
        try context.save()
    }

    @Test("a store written before #252 opens, with no analysis on its routes")
    func opensPreAnalysisStore() throws {
        try withTemporaryStoreURL(prefix: "RouteMigration") { url in
            try writeLegacyStore(at: url)

            let routes = try ModelContext(openStore(at: url)).fetch(FetchDescriptor<Route>())
            #expect(routes.count == 3)
            #expect(routes.allSatisfy { $0.terrainData == nil && $0.surfaceData == nil })
            #expect(routes.contains { $0.name == "Pilot Mountain" && $0.coordinates == Self.hilly.coordinates })
        }
    }

    @Test("backfill analyses the old routes that have elevation, and only those, once")
    func backfillFillsInOldRoutes() async throws {
        try await withTemporaryStoreURL(prefix: "RouteMigration") { url in
            try writeLegacyStore(at: url)
            let actor = RoutePersistenceActor(modelContainer: try openStore(at: url))

            // The route without `<ele>` is never touched. The stationary one has gain but analyses
            // to nil; it is marked so the second pass does not decode it again.
            #expect(try await actor.backfillRouteTerrain() == 2)
            #expect(try await actor.backfillRouteTerrain() == 0)

            let routes = try await actor.fetchRoutes()
            let hilly = try #require(routes.first { $0.name == "Pilot Mountain" })
            #expect(hilly.terrain == RouteTerrain.analyze(Self.hilly.coordinates))
            #expect(hilly.terrain?.climbs.first?.category == .cat3)
            #expect(routes.filter { $0.name != "Pilot Mountain" }.allSatisfy { $0.terrain == nil })
        }
    }
}
