import ComposableArchitecture
import Foundation
import os

private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "persistence")

/// Records that the rider ended a ride, in storage independent of SwiftData.
///
/// `finalizeRide` is the only writer of `Ride.endedAt`, and `fetchResumableRide` reads a
/// nil `endedAt` as "still in progress". So a failed finalize leaves no durable trace that
/// the ride is over, and crash recovery (#175) resumes a ride the rider already finished.
/// The correction cannot live in the store that just failed — hence a separate, dead
/// simple JSON file.
///
/// Deliberately *not* part of `PersistenceClient`: the whole point is to survive a
/// PersistenceClient failure, and folding it in would put the record back in the blast
/// radius it exists to escape. Deliberately not `@Shared` either — the reducer only writes
/// it, never renders it, and shared state in `State` would make every exhaustive
/// `TestStore` assert a persistence detail.
struct RideEndIntentClient: Sendable {
    var load: @Sendable () -> PendingRideEnd?
    var save: @Sendable (PendingRideEnd) -> Void
    var clear: @Sendable () -> Void
}

extension RideEndIntentClient: DependencyKey {
    static var liveValue: RideEndIntentClient {
        let url = URL.documentsDirectory.appending(component: "pending-ride-end.json")
        return RideEndIntentClient(
            load: {
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(PendingRideEnd.self, from: data)
            },
            save: { intent in
                do {
                    try JSONEncoder().encode(intent).write(to: url, options: .atomic)
                } catch {
                    // Best effort. A lost marker only costs the recovery this exists for;
                    // it must never take the ride-end sequence down with it.
                    logger.error("failed to record ride-end intent: \(error.localizedDescription, privacy: .public)")
                }
            },
            clear: { try? FileManager.default.removeItem(at: url) }
        )
    }

    /// Fresh in-memory store per dependency scope, so tests never touch Documents.
    static var testValue: RideEndIntentClient { .inMemory() }
    static var previewValue: RideEndIntentClient { .inMemory() }

    /// Shared explicitly when a test needs one ride's marker to survive into a simulated
    /// relaunch, the way the real file does.
    static func inMemory(initial: PendingRideEnd? = nil) -> RideEndIntentClient {
        let storage = LockIsolated(initial)
        return RideEndIntentClient(
            load: { storage.value },
            save: { intent in storage.setValue(intent) },
            clear: { storage.setValue(nil) }
        )
    }
}

extension DependencyValues {
    var rideEndIntentClient: RideEndIntentClient {
        get { self[RideEndIntentClient.self] }
        set { self[RideEndIntentClient.self] = newValue }
    }
}
