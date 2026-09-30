import ComposableArchitecture
import Foundation

/// In-memory ring buffer of `TrackPointDTO`s for the active ride, drained by the 30s
/// CoreData checkpoint (DataModel.md §5). A plain actor rather than a `PersistenceClient`-
/// style closure wrapper — this buffer is pure in-memory logic with no I/O to swap
/// between live/mock, unlike `RidePersistenceActor`.
actor RideDataBuffer {
    private let maxCapacity = 1_800 // 30 minutes at 1 Hz
    private var points: [TrackPointDTO] = []
    private var flushedCount = 0

    func append(_ point: TrackPointDTO) {
        points.append(point)
        if points.count > maxCapacity { points.removeFirst() }
    }

    func drainForFlush() -> [TrackPointDTO] {
        let toFlush = points
        points = []
        flushedCount += toFlush.count
        return toFlush
    }

    /// Drains the buffer into `write`. A batch that fails to write goes back to the front, ahead
    /// of anything appended meanwhile, so the next flush retries it in order (#345). A failed
    /// batch insert writes nothing, so the retry can't duplicate points.
    func flush(to write: @Sendable ([TrackPointDTO]) async throws -> Void) async throws {
        let batch = drainForFlush()
        guard !batch.isEmpty else { return }
        do {
            try await write(batch)
        } catch {
            points = batch + points
            flushedCount -= batch.count
            // Over capacity, the oldest go, as in `append`.
            if points.count > maxCapacity { points.removeFirst(points.count - maxCapacity) }
            throw error
        }
    }

    var totalPointCount: Int { flushedCount + points.count }
}

extension RideDataBuffer: DependencyKey {
    /// One shared instance app-wide — only one ride is ever active at a time (mirrors
    /// `CoreDataStack.shared`).
    static let liveValue = RideDataBuffer()
    /// Must be a computed `var`, not `let`: `swift-dependencies` re-invokes `testValue`
    /// once per test scope, but a `static let` initializes exactly once for the whole
    /// process, which would leak buffered points between tests via a shared singleton.
    static var testValue: RideDataBuffer { RideDataBuffer() }
}

extension DependencyValues {
    var rideDataBuffer: RideDataBuffer {
        get { self[RideDataBuffer.self] }
        set { self[RideDataBuffer.self] = newValue }
    }
}

extension SharedKey where Self == InMemoryKey<[UUID: Int]>.Default {
    /// Points each ride ended without, keyed by ride, when its final flush failed twice (#345).
    /// Written by `ActiveRideFeature`'s ride-end effect before the finalize; S10 reads and clears
    /// its ride's entry once that finalize lands. In memory: the dashboard that knows is gone by
    /// then, and the rider is told only on the screen that follows.
    static var unsavedTrackPoints: Self {
        Self[.inMemory("unsavedTrackPoints"), default: [:]]
    }
}
