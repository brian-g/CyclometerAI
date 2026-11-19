import ComposableArchitecture
import Foundation
import os

private let logger = Logger.cyclometer(.persistence)

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
///
/// One marker per ride (#583). A close-out whose finalize fails keeps its ride's marker, and
/// the next ride's Finish writes its own beside it rather than over it: a single slot lost
/// the first, and the next launch resumed that ride.
struct RideEndIntentClient: Sendable {
    /// Every ride's marker, in the order first written.
    var loadAll: @Sendable () -> [PendingRideEnd]
    /// Records this ride's marker, replacing any it already had. Other rides' are kept.
    var save: @Sendable (PendingRideEnd) -> Void
    /// Drops this ride's marker only.
    var clear: @Sendable (_ rideId: UUID) -> Void
}

extension RideEndIntentClient {
    /// This ride's marker, if its end is still waiting on a finalize.
    func load(_ rideId: UUID) -> PendingRideEnd? {
        loadAll().first { $0.rideId == rideId }
    }
}

extension RideEndIntentClient: DependencyKey {
    static var liveValue: RideEndIntentClient {
        .file(at: URL.documentsDirectory.appending(component: "pending-ride-end.json"))
    }

    /// The live store, at a location a test can choose.
    static func file(at url: URL) -> RideEndIntentClient {
        .store(
            read: {
                guard let data = try? Data(contentsOf: url) else { return [] }
                if let markers = try? JSONDecoder().decode([PendingRideEnd].self, from: data) {
                    return markers
                }
                // Written before #583, when the file held one marker.
                return (try? JSONDecoder().decode(PendingRideEnd.self, from: data)).map { [$0] } ?? []
            },
            write: { markers in
                guard !markers.isEmpty else {
                    try? FileManager.default.removeItem(at: url)
                    return
                }
                do {
                    try JSONEncoder().encode(markers).write(to: url, options: .atomic)
                } catch {
                    // Best effort. A lost marker only costs the recovery this exists for;
                    // it must never take the ride-end sequence down with it.
                    logger.error("failed to record ride-end intent: \(error.localizedDescription, privacy: .public)")
                }
            }
        )
    }

    /// Fresh in-memory store per dependency scope, so tests never touch Documents.
    static var testValue: RideEndIntentClient { .inMemory() }
    static var previewValue: RideEndIntentClient { .inMemory() }

    /// Shared explicitly when a test needs one ride's marker to survive into a simulated
    /// relaunch, the way the real file does.
    static func inMemory(initial: PendingRideEnd? = nil) -> RideEndIntentClient {
        let storage = LockIsolated(initial.map { [$0] } ?? [])
        return .store(read: { storage.value }, write: { storage.setValue($0) })
    }

    /// The read-modify-write both stores share. Under one lock, so a Finish's save and a
    /// launch close-out's clear landing together can't drop each other's ride.
    private static func store(
        read: @escaping @Sendable () -> [PendingRideEnd],
        write: @escaping @Sendable ([PendingRideEnd]) -> Void
    ) -> RideEndIntentClient {
        let lock = NSLock()
        return RideEndIntentClient(
            loadAll: { lock.withLock { read() } },
            save: { intent in
                lock.withLock {
                    var markers = read()
                    if let index = markers.firstIndex(where: { $0.rideId == intent.rideId }) {
                        markers[index] = intent
                    } else {
                        markers.append(intent)
                    }
                    write(markers)
                }
            },
            clear: { rideId in
                lock.withLock { write(read().filter { $0.rideId != rideId }) }
            }
        )
    }
}

extension DependencyValues {
    var rideEndIntentClient: RideEndIntentClient {
        get { self[RideEndIntentClient.self] }
        set { self[RideEndIntentClient.self] = newValue }
    }
}
