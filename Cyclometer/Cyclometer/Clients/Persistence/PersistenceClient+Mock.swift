import Foundation

extension PersistenceClient {
    static func mock(
        trackPoints: [UUID: [TrackPointDTO]] = [:],
        rideExportMetadata: [UUID: RideExportMetadata] = [:],
        vehiclePassEvents: [UUID: [VehiclePassEventDTO]] = [:],
        resumableRide: RideSummaryUpdate? = nil,
        onFlush: @escaping @Sendable ([TrackPointDTO]) -> Void = { _ in },
        onCreateRide: @escaping @Sendable (UUID, Date) -> Void = { _, _ in },
        onUpdateRideSummary: @escaping @Sendable (RideSummaryUpdate) -> Void = { _ in },
        onFinalizeRide: @escaping @Sendable (UUID, Date, RideSummaryUpdate, URL?) -> Void = { _, _, _, _ in },
        onAppendVehiclePassEvents: @escaping @Sendable ([VehiclePassEventDTO]) -> Void = { _ in }
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
            createRide: { onCreateRide($0, $1) },
            updateRideSummary: { onUpdateRideSummary($0) },
            finalizeRide: { onFinalizeRide($0, $1, $2, $3) },
            appendVehiclePassEvents: { onAppendVehiclePassEvents($0) },
            fetchVehiclePassEvents: { vehiclePassEvents[$0] ?? [] },
            fetchResumableRide: { resumableRide }
        )
    }
}
