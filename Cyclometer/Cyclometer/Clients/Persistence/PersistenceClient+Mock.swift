import Foundation

extension PersistenceClient {
    static func mock(
        trackPoints: [UUID: [TrackPointDTO]] = [:],
        onFlush: @escaping @Sendable ([TrackPointDTO]) -> Void = { _ in },
        onCreateRide: @escaping @Sendable (UUID, Date) -> Void = { _, _ in },
        onUpdateRideSummary: @escaping @Sendable (RideSummaryUpdate) -> Void = { _ in },
        onFinalizeRide: @escaping @Sendable (UUID, Date, RideSummaryUpdate) -> Void = { _, _, _ in }
    ) -> PersistenceClient {
        PersistenceClient(
            flushTrackPoints: { onFlush($0) },
            fetchTrackPoints: { trackPoints[$0] ?? [] },
            createRide: { onCreateRide($0, $1) },
            updateRideSummary: { onUpdateRideSummary($0) },
            finalizeRide: { onFinalizeRide($0, $1, $2) }
        )
    }
}
