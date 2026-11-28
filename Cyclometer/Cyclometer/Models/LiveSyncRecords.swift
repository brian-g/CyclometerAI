import ComposableArchitecture
import Foundation

/// Every ride's Strava record written since launch (#632), so S15, S14 and S12.1 follow an upload
/// as `SyncQueueFeature` moves it on, and a reset as S15 makes it, without reading the store
/// again. The live `PersistenceClient` publishes each write here after it lands: the store stays
/// the truth, and a screen lays this over the record it read.
struct LiveSyncRecords: Equatable, Sendable {
    /// `.some(nil)` is a record deleted since launch, so a screen holding the old one drops it.
    private var records: [UUID: RideSyncRecord?] = [:]

    /// The ride's record as last written, else `stored`, the one the screen read.
    func record(for rideId: UUID, stored: RideSyncRecord?) -> RideSyncRecord? {
        records[rideId] ?? stored
    }

    /// The ride's Strava status as last written, else `stored`, the one the screen read: S14 holds
    /// only the status.
    func status(for rideId: UUID, stored: SyncStatus?) -> SyncStatus? {
        if let written = records[rideId] { return written?.status }
        return stored
    }

    /// Records a write, or a delete with nil.
    mutating func set(_ record: RideSyncRecord?, for rideId: UUID) {
        records[rideId] = .some(record)
    }
}

extension SharedKey where Self == InMemoryKey<LiveSyncRecords>.Default {
    /// In memory: it only carries what changed since launch, and the store has the rest.
    static var liveStravaSyncRecords: Self {
        Self[.inMemory("liveStravaSyncRecords"), default: LiveSyncRecords()]
    }
}
