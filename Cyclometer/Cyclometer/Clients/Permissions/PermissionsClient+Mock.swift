import ComposableArchitecture
import Foundation

extension PermissionsClient {

    /// Deterministic, synchronous, scriptable per domain — for `TestStore` and previews.
    ///
    /// Holds real state rather than answering from a fixed table, because the behaviour
    /// worth testing is a *transition*: a domain seeded `.notDetermined` becomes whatever
    /// `onRequest` returns and stays there, and a domain seeded `.denied` is never asked
    /// at all. A stateless stub cannot express either.
    ///
    /// - Parameters:
    ///   - initial: Seed state per domain. Unlisted domains start `.notDetermined`.
    ///   - onRequest: What the rider "answers" when a prompt is actually presented.
    ///     Only ever called for a domain currently `.notDetermined` — the short-circuit
    ///     is part of what the mock models, so a test can assert the prompt never
    ///     appeared by counting calls.
    static func mock(
        initial: [PermissionDomain: PermissionState] = [:],
        onRequest: @escaping @Sendable (PermissionDomain) -> PermissionState = { _ in .granted }
    ) -> PermissionsClient {
        let box = MockPermissionsBox(initial: initial)
        return PermissionsClient(
            status:   { box.status(for: $0) },
            request:  { box.request($0, answer: onRequest) },
            statuses: { box.makeStream() }
        )
    }
}

/// `@unchecked Sendable`: a single `NSLock` guards every stored property.
private final class MockPermissionsBox: @unchecked Sendable {

    private var states: [PermissionDomain: PermissionState]
    private var subscribers: [Int: AsyncStream<PermissionChange>.Continuation] = [:]
    private var nextID = 0
    private let lock = NSLock()

    init(initial: [PermissionDomain: PermissionState]) {
        var seeded: [PermissionDomain: PermissionState] = [:]
        for domain in PermissionDomain.allCases {
            seeded[domain] = initial[domain] ?? .notDetermined
        }
        states = seeded
    }

    func status(for domain: PermissionDomain) -> PermissionState {
        lock.withLock { states[domain] ?? .notDetermined }
    }

    func request(
        _ domain: PermissionDomain,
        answer: @Sendable (PermissionDomain) -> PermissionState
    ) -> PermissionState {
        let current = lock.withLock { states[domain] ?? .notDetermined }
        guard current == .notDetermined else { return current }

        let resolved = answer(domain)
        let observers = lock.withLock { () -> [AsyncStream<PermissionChange>.Continuation] in
            states[domain] = resolved
            return Array(subscribers.values)
        }
        for o in observers { o.yield(PermissionChange(domain: domain, state: resolved)) }
        return resolved
    }

    func makeStream() -> AsyncStream<PermissionChange> {
        let (stream, continuation) = AsyncStream<PermissionChange>.makeStream()
        // Register and replay under one lock acquisition, so a change landing mid-setup
        // is either in the replay or in the stream — never dropped between the two.
        let id = lock.withLock { () -> Int in
            let current = nextID
            nextID += 1
            subscribers[current] = continuation
            for domain in PermissionDomain.allCases {
                continuation.yield(
                    PermissionChange(domain: domain, state: states[domain] ?? .notDetermined)
                )
            }
            return current
        }
        continuation.onTermination = { [weak self] _ in
            _ = self?.lock.withLock { self?.subscribers.removeValue(forKey: id) }
        }
        return stream
    }
}
