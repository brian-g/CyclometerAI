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
