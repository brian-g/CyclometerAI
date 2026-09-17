import ComposableArchitecture
import Foundation
import SwiftData
import Testing
@testable import Cyclometer

/// Waits until `condition` holds, and records an issue if it never does.
///
/// The BLE clients publish a state change *before* making the transport call that
/// follows it. `BLECSCClient.swift`'s `.connected` handler sets
/// `connectionState = .connected` — which wakes any test awaiting the state stream —
/// and only on the next line calls `discoverServices`. `VariaRadarClient` and
/// `BLEHRClient` have the same shape.
///
/// So awaiting the state stream is a sync point for the **state**, not for the call
/// the handler makes next. Asserting on the harness's call log immediately after one
/// is a race, and it is the kind that hides: on an idle machine the handler always
/// wins, so the suite is green locally and green in six consecutive runs, then fails
/// on a contended CI runner. `Harness.devices(matching:)` already solves this for the
/// device list, whose stream *is* a sync point for itself; this covers everything the
/// harness records out of band — call logs, counters, discovered-service lists.
///
/// The timeout is deliberately far longer than the wait ever legitimately needs (the
/// whole suite is ~8 seconds of work). It is not a performance assertion, and it is
/// not the `.timeLimit` trait that was tried and reverted twice — those capped a
/// whole test and so tripped on contention alone. This bounds one specific wait, so
/// exceeding it means the call is not coming, and the alternative to a bound is
/// hanging until the 30-minute job timeout with nothing to show for it.
func expectEventually(
    _ comment: @autoclosure () -> Comment? = nil,
    within timeout: Duration = .seconds(10),
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: @Sendable () -> Bool
) async {
    if condition() { return }

    // Cooperative yields first. When the client's handler is merely queued behind
    // this task — the overwhelmingly common case — it runs on the very next yield
    // and the wait costs nothing measurable.
    for _ in 0..<100 {
        await Task.yield()
        if condition() { return }
    }

    // Still not there, so the handler is genuinely delayed rather than just behind
    // us. Back off to sleeping: continuing to spin would compete for the very core
    // the handler needs, which is precisely the contention that got us here.
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        try? await Task.sleep(for: .milliseconds(5))
        if condition() { return }
    }

    #expect(condition(), comment() ?? "Condition never held within \(timeout).", sourceLocation: sourceLocation)
}

/// How long a `TestStore` drain may take before it counts as a hang.
///
/// `TestStore.finish(timeout:)` counts **real** nanoseconds, not `TestClock` time, so
/// any value here is coupled to how loaded the machine is. That is the same coupling
/// that got per-test `.timeLimit` traits reverted twice — see the note in
/// `.github/workflows/tests.yml` — and it applies just as much to a drain deadline.
///
/// The two suites that use this (`RideRecordingTests`, `RideEndFailureTests`) are also
/// exactly the two that failed on CI on 2026-09-07 while passing on every local run.
/// They had 5 seconds against a suite that executes in ~8, which is not a lot of room
/// on a contended runner.
///
/// Generous on purpose. A longer deadline cannot mask a failure — it only delays
/// reporting a genuine hang, and this is still a small fraction of the 30-minute job
/// timeout that exists to catch exactly that.
let effectDrainTimeout: Duration = .seconds(30)

/// Fetch a `Ride` row without asserting on its absence.
///
/// `expectEventually` predicates run while the ride-end pipeline is still in flight, so
/// "no row yet" is the expected intermediate state there, not a failure. The suites'
/// own `fetchRide` helpers use `#require` and would record an issue on every poll.
func fetchRideIfPresent(_ id: UUID, from swiftDataStack: SwiftDataStack) -> Ride? {
    let context = ModelContext(swiftDataStack.container)
    var descriptor = FetchDescriptor<Ride>(predicate: #Predicate { $0.id == id })
    descriptor.fetchLimit = 1
    return try? context.fetch(descriptor).first
}

// MARK: - SwiftData store helpers

/// Runs `body` against a unique on-disk store URL, then removes the store and everything
/// SwiftData put beside it.
///
/// On disk rather than `isStoredInMemoryOnly` by necessity: an in-memory store has nothing
/// to migrate *from*, and it never spills an `.externalStorage` attribute to its own file,
/// so neither migration nor blob fidelity is observable there.
///
/// The cleanup covers the `_SUPPORT` directory as well as the SQLite sidecars. That
/// directory is where `.externalStorage` payloads actually land, so a suite that writes a
/// large polyline to force externalization leaks real bytes per run without it — dozens of
/// orphaned `_SUPPORT` directories had already accumulated in the simulator container from
/// the earlier version of this helper, which only deleted the three SQLite files.
///
/// Either overload records an issue if `body` leaves the store open: deleting a database SQLite
/// still has open is what `vnode unlinked while in use` reports (#242).
func withTemporaryStoreURL(
    prefix: String,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ body: (URL) throws -> Void
) throws {
    let url = temporaryStoreURL(prefix: prefix)
    defer { removeStore(at: url) }
    try body(url)
    let open = openStoreFiles(at: url)
    #expect(open.isEmpty, "the store is still open at cleanup: \(open)", sourceLocation: sourceLocation)
}

/// `withTemporaryStoreURL`'s async twin, for suites whose work goes through an actor.
func withTemporaryStoreURL(
    prefix: String,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ body: (URL) async throws -> Void
) async throws {
    let url = temporaryStoreURL(prefix: prefix)
    defer { removeStore(at: url) }
    try await body(url)
    await expectStoreClosed(at: url, sourceLocation: sourceLocation)
}

/// Waits until nothing in the process has the store at `url` open, and records an issue if
/// something still does.
///
/// A container handed to a `TestStore` outlives the store. swift-dependencies keeps the
/// `DependencyValues` of every object a `withDependencies` operation returns in a global table
/// (`DependencyObjects` in its `WithDependencies.swift`), weak on the object but strong on the
/// values, and `TestStore.init` returns its `TestReducer` from one. An entry whose object is gone
/// is only swept by a `Task` that the *next* such call starts. So the last test store's
/// `persistenceClient`, and the container its actors hold, stay open until something else makes
/// that call. This makes it, and waits for the sweep (#242).
///
/// Call it before opening a new container on a store a test store has used: two containers
/// open on one file at once is the lock-contention flake 31edca0 removed.
func expectStoreClosed(at url: URL, sourceLocation: SourceLocation = #_sourceLocation) async {
    final class Sweep {}
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(10))
    repeat {
        _ = withDependencies { _ in } operation: { Sweep() }
        try? await Task.sleep(for: .milliseconds(5))
        if openStoreFiles(at: url).isEmpty { return }
    } while clock.now < deadline
    let open = openStoreFiles(at: url)
    #expect(open.isEmpty, "the store is still open: \(open)", sourceLocation: sourceLocation)
}

/// The names of the store's files this process has a descriptor open on.
private func openStoreFiles(at url: URL) -> [String] {
    let store = url.resolvingSymlinksInPath().path
    var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    return (0..<getdtablesize()).compactMap { descriptor in
        guard fcntl(descriptor, F_GETPATH, &path) != -1 else { return nil }
        let open = URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath().path
        return open.hasPrefix(store) ? (open as NSString).lastPathComponent : nil
    }
}

private func temporaryStoreURL(prefix: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        .appendingPathExtension("store")
}

private func removeStore(at url: URL) {
    let directory = url.deletingLastPathComponent()
    let name = url.deletingPathExtension().lastPathComponent
    for path in [url.path, url.path + "-wal", url.path + "-shm", url.path + "-journal"] {
        try? FileManager.default.removeItem(atPath: path)
    }
    // SwiftData writes external-storage payloads into a sibling dot-directory.
    try? FileManager.default.removeItem(at: directory.appendingPathComponent(".\(name)_SUPPORT"))
    try? FileManager.default.removeItem(at: directory.appendingPathComponent(".\(name).store_SUPPORT"))
}

/// Opens `url` with exactly the schema production loads, so a test can never drift from it.
func openStore(at url: URL) throws -> ModelContainer {
    try ModelContainer(
        for: SwiftDataStack.schema,
        configurations: [ModelConfiguration(schema: SwiftDataStack.schema, url: url)]
    )
}
