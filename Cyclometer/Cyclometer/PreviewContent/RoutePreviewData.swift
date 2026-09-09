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
