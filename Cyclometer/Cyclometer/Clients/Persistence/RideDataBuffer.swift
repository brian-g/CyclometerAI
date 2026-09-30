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
    /// The flush running now, which the next one waits for (#345).
    private var flushing: Task<Void, Never>?
    /// The stretch of the ride whose points will never be written: evicted over capacity, or
    /// discarded after the ride-end flush gave up (#345). Nil while nothing is lost.
    private var lost: ClosedRange<Date>?

    func append(_ point: TrackPointDTO) {
        points.append(point)
        evictOverCapacity()
    }

    func drainForFlush() -> [TrackPointDTO] {
        let toFlush = points
        points = []
        flushedCount += toFlush.count
        return toFlush
    }

    /// Drains the buffer into `write`, one flush at a time: a flush waits for the one in flight,
    /// so it also carries any batch that flush put back. A batch that fails to write goes back to
    /// the front, ahead of anything appended meanwhile, and the next flush retries it in order
    /// (#345). A failed batch insert writes nothing, so the retry can't duplicate points.
    ///
    /// The write runs to the end even if the caller is cancelled — a flush torn down with the
    /// dashboard must still put back what it couldn't write.
    func flush(to write: @escaping @Sendable ([TrackPointDTO]) async throws -> Void) async throws {
        let previous = flushing
        let attempt = Task {
            await previous?.value
            try await writeBatch(write)
        }
        flushing = Task { _ = try? await attempt.value }
        try await attempt.value
    }

    private func writeBatch(_ write: @Sendable ([TrackPointDTO]) async throws -> Void) async throws {
        let batch = drainForFlush()
        guard !batch.isEmpty else { return }
        do {
            try await write(batch)
        } catch {
            points = batch + points
            flushedCount -= batch.count
            evictOverCapacity()
            throw error
        }
    }

    /// Gives up on every unwritten point, counting them lost rather than flushed.
    func discardUnwritten() {
        markLost(points)
        points = []
    }

    /// The stretch lost since the last call, which it clears.
    func takeLost() -> ClosedRange<Date>? {
        defer { lost = nil }
        return lost
    }

    var totalPointCount: Int { flushedCount + points.count }

    /// Only a buffer whose flushes keep failing reaches capacity, so what goes is lost.
    private func evictOverCapacity() {
        guard points.count > maxCapacity else { return }
        let evicted = points.prefix(points.count - maxCapacity)
        markLost(evicted)
        points.removeFirst(evicted.count)
    }

    private func markLost(_ gone: some Collection<TrackPointDTO>) {
        guard let first = gone.map(\.timestamp).min(), let last = gone.map(\.timestamp).max() else { return }
        lost = lost.map { min($0.lowerBound, first)...max($0.upperBound, last) } ?? first...last
    }
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

extension SharedKey where Self == InMemoryKey<[UUID: ClosedRange<Date>]>.Default {
    /// The stretch of track each ride ended without, keyed by ride (#345). Written by
    /// `ActiveRideFeature`'s ride-end effect before the finalize; S10 clears its ride's entry once
    /// it has told the rider. In memory: the dashboard that knows is gone by then, and the rider is
    /// told only on the screen that follows.
    static var unsavedTrack: Self {
        Self[.inMemory("unsavedTrack"), default: [:]]
    }
}
