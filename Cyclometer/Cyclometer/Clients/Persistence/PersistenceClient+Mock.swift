import Foundation

extension PersistenceClient {
    static func mock(
        trackPoints: [UUID: [TrackPointDTO]] = [:],
        rideExportMetadata: [UUID: RideExportMetadata] = [:],
        rideStats: [UUID: RideStats] = [:],
        vehiclePassEvents: [UUID: [VehiclePassEventDTO]] = [:],
        resumableRide: RideSummaryUpdate? = nil,
        rides: [RideListSummary] = [],
        routes: [RouteSummary] = [],
        routeDetails: [UUID: RouteDetail] = [:],
        importResult: RouteSummary? = nil,
        ridesByRoute: [UUID: [RouteRideSummary]] = [:],
        rideIdsMissingMapThumbnail: [UUID] = [],
        mapThumbnails: [UUID: RideMapThumbnailData] = [:],
        onFlush: @escaping @Sendable ([TrackPointDTO]) -> Void = { _ in },
        onCreateRide: @escaping @Sendable (UUID, Date, RouteReference?) -> Void = { _, _, _ in },
        onUpdateRideSummary: @escaping @Sendable (RideSummaryUpdate) -> Void = { _ in },
        onFinalizeRide: @escaping @Sendable (UUID, Date, RideSummaryUpdate, URL?) -> Void = { _, _, _, _ in },
        onSaveRideMapThumbnail: @escaping @Sendable (UUID, Data, Data) -> Void = { _, _, _ in },
        onAppendVehiclePassEvents: @escaping @Sendable ([VehiclePassEventDTO]) -> Void = { _ in },
        onDeleteRide: @escaping @Sendable (UUID) -> Void = { _ in },
        onImportRoute: @escaping @Sendable (ImportedRoute) -> Void = { _ in },
        onDeleteRoute: @escaping @Sendable (UUID) -> Void = { _ in },
        onSaveRouteSurface: @escaping @Sendable (UUID, RouteSurfaceBreakdown) -> Void = { _, _ in },
        backfilledRouteCount: Int = 0
    ) -> PersistenceClient {
        PersistenceClient(
            flushTrackPoints: { onFlush($0) },
            fetchTrackPoints: { trackPoints[$0] ?? [] },
            fetchRide: {
                // Matches live's throw-on-unknown-rideId behavior (RidePersistenceActor),
                // unlike fetchTrackPoints/fetchVehiclePassEvents where an empty result is
                // itself the faithful live behavior for an unknown rideId.
                guard let metadata = rideExportMetadata[$0] else { throw PersistenceError.rideNotFound }
                return metadata
            },
            fetchRideStats: {
                // Throws for an unknown id, like `fetchRide` above and the live actor.
                guard let stats = rideStats[$0] else { throw PersistenceError.rideNotFound }
                return stats
            },
            createRide: { onCreateRide($0, $1, $2) },
            updateRideSummary: { onUpdateRideSummary($0) },
            finalizeRide: { onFinalizeRide($0, $1, $2, $3) },
            saveRideMapThumbnail: { onSaveRideMapThumbnail($0, $1, $2) },
            fetchRideIdsMissingMapThumbnail: { rideIdsMissingMapThumbnail },
            fetchRideMapThumbnail: { mapThumbnails[$0] },
            appendVehiclePassEvents: { onAppendVehiclePassEvents($0) },
            fetchVehiclePassEvents: { vehiclePassEvents[$0] ?? [] },
            deleteRide: { onDeleteRide($0) },
            fetchResumableRide: { resumableRide },
            fetchRides: { rides },
            importRoute: {
                onImportRoute($0)
                // Unscripted, this runs the caller's route through the same derivation the
                // live path uses, so a feature test sees real distance and elevation
                // without standing up a store. `importResult` is for the tests that need a
                // known id back: the live path mints a fresh UUID below the dependency
                // boundary, so `$0.uuid = .incrementing` cannot reach it.
                return importResult ?? RouteSummary(imported: $0)
            },
            fetchRoutes: { routes },
            fetchRoute: { routeDetails[$0] },
            deleteRoute: { onDeleteRoute($0) },
            fetchRouteRides: { ridesByRoute[$0] ?? [] },
            saveRouteSurface: { onSaveRouteSurface($0, $1) },
            backfillRouteTerrain: { backfilledRouteCount }
        )
    }
}
