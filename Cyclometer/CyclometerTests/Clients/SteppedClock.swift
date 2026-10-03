import Foundation

/// A test clock for stepping a reconnect backoff ladder without yielding (#373).
///
/// `TestClock.advance` calls `Task.megaYield()` several times, and every megaYield runs 20
/// detached `.background`-priority tasks one after another. A Mac schedules those at once; the
/// CI VM throttles background QoS, so each advance took 10–30 s there, and the 10-step ladder in
/// `BLECSCIntegrationTests.reconnectGivesUp` took 150 s against 0.008 s locally.
///
/// This clock never yields. `advanceToNextSleep()` waits until the code under test is actually
/// sleeping and then resumes it directly, so the test needs no scheduling luck, and a sleep that
/// starts late can't be skipped. TCA `TestStore` suites keep `TestClock`; they aren't slow on CI.
///
/// One test task drives it: only one `advanceToNextSleep()` may wait at a time.
final class SteppedClock: Clock, @unchecked Sendable {
    struct Instant: InstantProtocol {
        fileprivate var offset: Duration

        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private struct Sleeper {
        let id: UUID
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let lock = NSLock()
    private var current = Instant(offset: .zero)
    private var sleepers: [Sleeper] = []
    /// The test, waiting in `advanceToNextSleep()` for something to sleep.
    private var waiter: CheckedContinuation<Void, Never>?

    var now: Instant { lock.withLock { current } }
    var minimumResolution: Duration { .zero }

    /// Nothing is sleeping. Cancelling a sleep removes it at once, so after the code under test
    /// cancels its backoff and publishes that it has, this holds without waiting.
    var isIdle: Bool { lock.withLock { sleepers.isEmpty } }

    func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                // Under the lock, so a cancel that lands before the sleeper is recorded is seen
                // here rather than missed by `onCancel`.
                let (immediate, waiting) = lock.withLock { () -> (Result<Void, any Error>?, CheckedContinuation<Void, Never>?) in
                    if Task.isCancelled { return (.failure(CancellationError()), nil) }
                    if deadline <= current { return (.success(()), nil) }
                    sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    defer { waiter = nil }
                    return (nil, waiter)
                }
                if let immediate { continuation.resume(with: immediate) }
                waiting?.resume()
            }
        } onCancel: {
            let cancelled = lock.withLock { () -> Sleeper? in
                guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return nil }
                return sleepers.remove(at: index)
            }
            cancelled?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Waits until something is sleeping, moves the clock to the earliest deadline, wakes every
    /// sleep due by then, and returns how far the clock moved — the length of that sleep, so a
    /// test can assert a backoff ladder step by step.
    func advanceToNextSleep() async -> Duration {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let isSleeping = lock.withLock {
                if sleepers.isEmpty { waiter = continuation }
                return !sleepers.isEmpty
            }
            if isSleeping { continuation.resume() }
        }
        let (moved, due) = lock.withLock { () -> (Duration, [Sleeper]) in
            let next = sleepers.map(\.deadline).min()!
            let moved = current.duration(to: next)
            current = next
            return (moved, takeDueLocked())
        }
        due.forEach { $0.continuation.resume() }
        return moved
    }

    /// Moves the clock on by `duration` without waiting for anything to sleep, wakes whatever is
    /// due, then yields so the woken work and any events still queued can run. For "nothing happens
    /// even after a long time" checks, which can only prove a negative after giving it time.
    ///
    /// The yields run at the caller's priority. `TestClock` gave the same time through
    /// `megaYield`'s `.background` tasks, which is what made it slow on CI.
    func advance(by duration: Duration) async {
        let due = lock.withLock {
            current = current.advanced(by: duration)
            return takeDueLocked()
        }
        due.forEach { $0.continuation.resume() }
        for _ in 0..<Self.yieldsAfterAdvance { await Task.yield() }
    }

    /// As many yields as `TestClock.advance` gave through its three megaYields (3 × 20).
    private static let yieldsAfterAdvance = 60

    /// Removes and returns the sleepers due by `current`. Must hold the lock.
    private func takeDueLocked() -> [Sleeper] {
        let due = sleepers.filter { $0.deadline <= current }
        sleepers.removeAll { $0.deadline <= current }
        return due
    }
}
