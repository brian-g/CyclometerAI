import ComposableArchitecture

/// Lets one backfill run at a time; later callers queue in order (#248 review). A dependency
/// rather than a `static` so tests running in parallel each get their own and never wait on
/// one another's work.
actor BackfillGate {
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run<T: Sendable>(_ operation: @Sendable () async -> T) async -> T {
        if isBusy {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            isBusy = true
        }
        // Handed straight to the next waiter, so the gate never reads free while one waits.
        defer {
            if waiters.isEmpty { isBusy = false } else { waiters.removeFirst().resume() }
        }
        return await operation()
    }
}

/// Shared by `RideMapThumbnail.backfill` and `RouteMapThumbnail.backfill`.
private enum MapThumbnailGateKey: DependencyKey {
    static let liveValue = BackfillGate()
    static var testValue: BackfillGate { BackfillGate() }
}

/// `RideHealthWorkout.backfill`'s own (#277), so a workout never queues behind map tiles
/// coming over the network.
private enum HealthWorkoutGateKey: DependencyKey {
    static let liveValue = BackfillGate()
    static var testValue: BackfillGate { BackfillGate() }
}

extension DependencyValues {
    var mapThumbnailGate: BackfillGate {
        get { self[MapThumbnailGateKey.self] }
        set { self[MapThumbnailGateKey.self] = newValue }
    }

    var healthWorkoutGate: BackfillGate {
        get { self[HealthWorkoutGateKey.self] }
        set { self[HealthWorkoutGateKey.self] = newValue }
    }
}
