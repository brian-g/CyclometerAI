import Foundation
import os

// Stream live: Console.app / Xcode console, filter subsystem "xyz.acmeapps.ride".
private let logger = Logger.cyclometer(.persistence)

/// A rider's intent to end a ride, recorded outside SwiftData.
///
/// `finalizeRide` is the only thing that sets `Ride.endedAt`, and `fetchResumableRide`
/// treats a nil `endedAt` as "this ride is still in progress"
/// (`RidePersistenceActor.swift:31-39`, `:84-96`). So when that one save fails, nothing
/// durable records that the ride is over, and #175's crash recovery resumes a ride the
/// rider already finished — restarting the recorder and reconnecting sensors.
///
/// The fix has to live in a store that a SwiftData failure cannot take out with it, so
/// the intent is written to file storage the moment Finish is confirmed and cleared only
/// once `finalizeRide` actually succeeds. A resumable ride whose marker is still present at
/// launch never had its finalize land, and is closed out instead of resumed.
///
/// Kept per ride (`RideEndIntentClient`, #583): a marker is cleared only by its own ride's
/// finalize, never by another ride's Finish.
struct PendingRideEnd: Codable, Equatable, Sendable {
    var rideId: UUID
    var endedAt: Date
    /// Carried so a successful export isn't orphaned by a failed finalize: the GPX file
    /// is already on disk, and only the row pointing at it failed to save.
    var gpxFileURL: URL?
    /// The totals Finish worked out (#607). Without them the close-out writes the summary read
    /// back from the row, which is only as current as the last checkpoint that saved. And when
    /// the finalize failed, the pause checkpoint before it most likely failed too. Its `finish`
    /// is nil, because the marker is written before the finish stats are worked out. That
    /// leaves the closed-out ride owed them (`RideFinishStats.backfill`).
    var summary: RideSummaryUpdate? = nil
}

extension PendingRideEnd {
    /// Never fails over `summary`. The markers file decodes as one array, so a marker that
    /// threw would take every ride's marker with it. Instead, a marker written before #607
    /// (no summary) decodes with none, and so does one whose summary a later
    /// `RideSummaryUpdate` field can't read. Either way the close-out falls back to the
    /// checkpoint summary.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rideId = try container.decode(UUID.self, forKey: .rideId)
        self.rideId = rideId
        endedAt = try container.decode(Date.self, forKey: .endedAt)
        gpxFileURL = try container.decodeIfPresent(URL.self, forKey: .gpxFileURL)
        do {
            summary = try container.decodeIfPresent(RideSummaryUpdate.self, forKey: .summary)
        } catch {
            // Logged, so a close-out with the checkpoint's totals isn't mistaken for a missing one.
            logger.error("ride-end marker for \(rideId, privacy: .public) has an unreadable summary; its close-out falls back to the checkpoint's: \(error.localizedDescription, privacy: .public)")
            summary = nil
        }
    }
}
