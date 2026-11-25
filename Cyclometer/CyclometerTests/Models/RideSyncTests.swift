import Testing
import Foundation
@testable import Cyclometer

/// The values a ride's sync records and the AppPreferences document persist by raw value
/// (DataModel.md §3.1, §3.8). Renaming a case silently orphans every record that used it.
@Suite("Ride sync")
struct RideSyncTests {

    /// `.processing` (#628): uploaded, awaiting Strava's activity id, so a ride quit mid-poll
    /// resumes polling rather than uploading again.
    @Test("A sync record round-trips through JSON, processing included")
    func syncRecordRoundTrips() throws {
        let record = RideSyncRecord(
            service: .strava,
            status: .processing,
            syncedAt: nil,
            remoteActivityId: nil,
            errorMessage: nil
        )

        let decoded = try JSONDecoder().decode(RideSyncRecord.self, from: JSONEncoder().encode(record))

        #expect(decoded.service == .strava)
        #expect(decoded.status == .processing)
        #expect(decoded.syncedAt == nil)
        #expect(decoded.remoteActivityId == nil)
        #expect(decoded.errorMessage == nil)
    }

    @Test("Every sync status is pinned")
    func syncStatusRawValues() {
        let all: [SyncStatus] = [.pending, .uploading, .processing, .synced, .failed]
        #expect(all.map(\.rawValue) == ["pending", "uploading", "processing", "synced", "failed"])
    }

    @Test("Every service is pinned")
    func externalServiceRawValues() {
        #expect(ExternalService.allCases.map(\.rawValue) == ["strava", "rideWithGPS", "tribosDotStudio", "komoot"])
    }

    /// The keys of `AppPreferences.syncDestinationDefaults`. Apple Health plus every service, and
    /// each name reads back as the destination it came from.
    @Test("Every sync destination is pinned, and its name reads back")
    func syncDestinationRawValues() {
        let all = [SyncDestination.appleHealth] + ExternalService.allCases.map(SyncDestination.service)
        #expect(all.map(\.rawValue) == ["appleHealth", "strava", "rideWithGPS", "tribosDotStudio", "komoot"])
        #expect(all.map { SyncDestination(rawValue: $0.rawValue) } == all)
        #expect(SyncDestination(rawValue: "garminConnect") == nil)
    }
}
