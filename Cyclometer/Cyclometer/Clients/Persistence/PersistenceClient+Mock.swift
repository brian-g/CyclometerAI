import Foundation

extension PersistenceClient {
    static func mock(
        trackPoints: [UUID: [TrackPointDTO]] = [:],
        onFlush: @escaping @Sendable ([TrackPointDTO]) -> Void = { _ in }
    ) -> PersistenceClient {
        PersistenceClient(
            flushTrackPoints: { onFlush($0) },
            fetchTrackPoints: { trackPoints[$0] ?? [] }
        )
    }
}
