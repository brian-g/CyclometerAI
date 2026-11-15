import Testing
import ComposableArchitecture
@testable import Cyclometer

/// A clock whose every sleep throws an error that isn't `CancellationError`, while the
/// sleeping task is not cancelled.
///
/// A ladder that swallows the error loops straight back into the next sleep without
/// waiting, which in the test host is a hot loop that never ends. To make that regression
/// a failing count instead of a hang, the clock cancels the sleeping task itself once it
/// has been asked to sleep `bound` times: any ladder honours cancellation, so it stops
/// there and the test can read how often it spun.
private final class FailingClock: Clock, @unchecked Sendable {
    struct SleepFailed: Error {}

    let bound: Int
    let sleeps = LockIsolated(0)

    init(bound: Int) { self.bound = bound }

    var now: ContinuousClock.Instant { .now }
    var minimumResolution: Duration { .zero }

    func sleep(until deadline: ContinuousClock.Instant, tolerance: Duration? = nil) async throws {
        let count = sleeps.withValue { count -> Int in
            count += 1
            return count
        }
        if count >= bound { withUnsafeCurrentTask { $0?.cancel() } }
        throw SleepFailed()
    }
}

@Suite("BLEReconnectLadder")
struct BLEReconnectLadderTests {

    @Test("Backoff ladder is 1, 2, 4, 8, 16 then capped at 30 seconds")
    func backoffLadder() {
        let expected: [Duration] = [
            .seconds(1), .seconds(2), .seconds(4), .seconds(8),
            .seconds(16), .seconds(30), .seconds(30), .seconds(30),
        ]
        for (attempt, delay) in expected.enumerated() {
            #expect(BLEReconnectLadder.reconnectDelay(attempt: attempt) == delay)
        }
    }

    @Test("Each rung sleeps its delay, then connects with a 1-based attempt number, until told to stop")
    func runsTheLadderUntilNoLongerReconnecting() async {
        let clock = SteppedClock()
        let attempts = LockIsolated<[Int]>([])
        let ladder = Task {
            await BLEReconnectLadder.run(
                clock: clock,
                isStillReconnecting: { attempts.value.count < 7 },
                connect: { attempt in attempts.withValue { $0.append(attempt) } }
            )
        }

        // Seven rungs connect; the eighth wakes to find reconnection over and returns.
        var delays: [Duration] = []
        for _ in 0..<8 { delays.append(await clock.advanceToNextSleep()) }
        await ladder.value

        #expect(delays == [1, 2, 4, 8, 16, 30, 30, 30].map { .seconds($0) })
        #expect(attempts.value == [1, 2, 3, 4, 5, 6, 7])
        #expect(clock.isIdle)
    }

    /// The loops this helper replaced used `try? await clock.sleep`. A sleep that throws
    /// without the task being cancelled then cost no time at all, and the next line issued
    /// another `connect`.
    @Test("A sleep that throws while the task is not cancelled ends the ladder rather than spinning")
    func throwingSleepEndsTheLadder() async {
        let clock = FailingClock(bound: 50)
        let connects = LockIsolated(0)
        let ladder = Task {
            await BLEReconnectLadder.run(
                clock: clock,
                isStillReconnecting: { true },
                connect: { _ in connects.withValue { $0 += 1 } }
            )
        }
        await ladder.value

        #expect(clock.sleeps.value == 1)
        #expect(connects.value == 0)
    }
}
