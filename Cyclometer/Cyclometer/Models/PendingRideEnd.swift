import Foundation

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
/// once `finalizeRide` actually succeeds. A marker still present at launch means the
/// previous finalize never landed, and the ride is closed out instead of resumed.
struct PendingRideEnd: Codable, Equatable, Sendable {
    var rideId: UUID
    var endedAt: Date
    /// Carried so a successful export isn't orphaned by a failed finalize: the GPX file
    /// is already on disk, and only the row pointing at it failed to save.
    var gpxFileURL: URL?
}
