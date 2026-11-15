import Foundation

/// The reconnect backoff ladder (BLE.md §6.1), shared by every client that reconnects by
/// re-issuing `connect()`: `BLECSCClient` and `VariaRadarClient`. `BLEHRClient` reconnects by
/// rescanning instead and has no ladder.
///
/// One copy on purpose (#558). The two clients each carried their own loop, and the
/// 2026-11-09 bug came from them drifting apart: only CSC had grown an attempt cap.
enum BLEReconnectLadder {
    /// 1, 2, 4, 8, 16, then 30 s for every attempt after.
    static func reconnectDelay(attempt: Int) -> Duration {
        .seconds(min(1 << min(attempt, 5), 30))
    }

    /// Sleep for the next rung, then call `connect` with the 1-based attempt number. Repeats
    /// until the task is cancelled, `isStillReconnecting` returns false, or the sleep throws.
    ///
    /// There is no attempt cap: how long a sensor stays out of range doesn't tell us it's
    /// lost (BLE.md §6.1).
    ///
    /// A throwing sleep ends the ladder whether or not the task was cancelled. The loops this
    /// replaced used `try? await clock.sleep`, which turned a sleep that throws for any other
    /// reason into no delay at all: a hot loop of `connect` calls. Nothing retries a clock
    /// that has stopped sleeping.
    static func run(
        clock: any Clock<Duration>,
        isStillReconnecting: () -> Bool,
        connect: (_ attempt: Int) async -> Void
    ) async {
        var attempt = 0
        while true {
            do {
                try await clock.sleep(for: reconnectDelay(attempt: attempt))
            } catch {
                return
            }
            guard !Task.isCancelled, isStillReconnecting() else { return }
            attempt += 1
            await connect(attempt)
        }
    }
}
