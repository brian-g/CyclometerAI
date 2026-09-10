import Foundation

/// Saved-route fixtures for S19's previews and snapshot references.
///
/// `RouteSummary` values rather than `RouteStub`s: these go through the same
/// `PersistenceClient.mock(routes:)` seam the real screen reads, so a preview exercises the
/// production path instead of a parallel one.
extension RouteSummary {
    static func preview(
        id: UUID,
        name: String,
        terrain: String?,
        distanceMeters: Double,
        elevationGainMeters: Double?,
        bounds: RouteBounds,
        importedDaysAgo: Int
    ) -> RouteSummary {
        RouteSummary(
            id: id,
            name: name,
            terrainDescription: terrain,
            // Fixed, not `.now`: a snapshot reference recorded against a moving date would
            // differ from the next run's.
            importedAt: Date(timeIntervalSince1970: 1_800_000_000
                             - Double(importedDaysAgo) * 86_400),
            distanceMeters: distanceMeters,
            coordinateCount: 512,
            elevationGainMeters: elevationGainMeters,
            elevationLossMeters: elevationGainMeters,
            bounds: bounds
        )
    }

    /// Four routes around Cupertino, newest first — the order `fetchRoutes` returns. One
    /// carries no terrain description, which is the nil-`<desc>` GPX case the row has to
    /// render as distance alone.
    static let previewRoutes: [RouteSummary] = [
        .preview(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "River Loop", terrain: "Rolling terrain",
            distanceMeters: 36_050, elevationGainMeters: 256,
            bounds: RouteBounds(minLatitude: 37.3200, maxLatitude: 37.3500,
                                minLongitude: -122.0500, maxLongitude: -122.0000),
            importedDaysAgo: 1
        ),
        .preview(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Summit Climb", terrain: "2,450 ft of climbing",
            distanceMeters: 51_180, elevationGainMeters: 747,
            bounds: RouteBounds(minLatitude: 37.2900, maxLatitude: 37.3400,
                                minLongitude: -122.1400, maxLongitude: -122.0800),
            importedDaysAgo: 4
        ),
        .preview(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: "Tempo Flats", terrain: "Fast and flat",
            distanceMeters: 29_130, elevationGainMeters: 64,
            bounds: RouteBounds(minLatitude: 37.3600, maxLatitude: 37.3800,
                                minLongitude: -122.0300, maxLongitude: -121.9800),
            importedDaysAgo: 11
        ),
        .preview(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            name: "Coffee Spin", terrain: nil,
            distanceMeters: 20_280, elevationGainMeters: nil,
            bounds: RouteBounds(minLatitude: 37.3300, maxLatitude: 37.3450,
                                minLongitude: -122.0200, maxLongitude: -122.0050),
            importedDaysAgo: 25
        )
    ]
}

/// Geometry for `RouteSummary.previewRoutes`.
///
/// `RouteSummary` deliberately carries none (`Route.swift:139-140`), so previews and the
/// reducer tests that exercise the map filter read these through
/// `PersistenceClient.mock(routes:routeDetails:)` — the same `fetchRoute` seam
/// `RoutesFeature.loadMissingPolylines` uses live, rather than hand-seeding `state.polylines`
/// with geometry no production path would have produced.
extension RouteDetail {

    /// Straight legs between the corners named, each one inside its summary's stored bounds so
    /// the bounding-box pre-reject and the exact segment test agree about these routes.
    static func preview(_ summary: RouteSummary, _ coordinates: [RouteCoordinate]) -> RouteDetail {
        RouteDetail(summary: summary, coordinates: coordinates, cuePoints: [])
    }

    static let previewRouteDetails: [UUID: RouteDetail] = {
        let routes = RouteSummary.previewRoutes

        // River Loop — closed: the last point returns to the first, which is the case
        // `RouteMapContent` collapses to a single flag rather than stacking a checkered one on
        // top of the start.
        let riverLoop = Self.preview(routes[0], [
            .init(latitude: 37.3200, longitude: -122.0500, elevationMeters: 30),
            .init(latitude: 37.3500, longitude: -122.0500, elevationMeters: 96),
            .init(latitude: 37.3500, longitude: -122.0000, elevationMeters: 150),
            .init(latitude: 37.3200, longitude: -122.0000, elevationMeters: 74),
            .init(latitude: 37.3200, longitude: -122.0500, elevationMeters: 30)
        ])

        // Summit Climb — a diagonal, so its bounding box holds two large corners the line
        // never enters. That is the shape a box-only viewport test gets wrong.
        let summitClimb = Self.preview(routes[1], [
            .init(latitude: 37.2900, longitude: -122.1400, elevationMeters: 60),
            .init(latitude: 37.3100, longitude: -122.1100, elevationMeters: 340),
            .init(latitude: 37.3400, longitude: -122.0800, elevationMeters: 807)
        ])

        let tempoFlats = Self.preview(routes[2], [
            .init(latitude: 37.3600, longitude: -122.0300, elevationMeters: 12),
            .init(latitude: 37.3700, longitude: -122.0050, elevationMeters: 40),
            .init(latitude: 37.3800, longitude: -121.9800, elevationMeters: 20)
        ])

        // Coffee Spin — the nil-`<ele>` case, so its points carry no elevation at all rather
        // than a confident zero.
        let coffeeSpin = Self.preview(routes[3], [
            .init(latitude: 37.3300, longitude: -122.0200, elevationMeters: nil),
            .init(latitude: 37.3450, longitude: -122.0050, elevationMeters: nil)
        ])

        return Dictionary(
            uniqueKeysWithValues: [riverLoop, summitClimb, tempoFlats, coffeeSpin]
                .map { ($0.summary.id, $0) }
        )
    }()
}
