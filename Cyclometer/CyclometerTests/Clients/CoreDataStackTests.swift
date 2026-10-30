import Foundation
import Testing
@testable import Cyclometer

/// #480: building a `CoreDataStack` must never wait on the main thread. Tests build one per
/// case on the cooperative pool, and when the stack used to configure its main-queue
/// `viewContext` — each setter a `performBlockAndWait` onto main — the parallel
/// `PersistenceClientTests` parked every pool thread on a main thread that a MapKit teardown
/// was holding, and full local runs hung.
@Suite("CoreDataStack")
struct CoreDataStackTests {

    /// Main is held for the whole build, as the MapKit teardown held it. A stack that needs
    /// main can't finish until the wait times out, however long that is, so the timeout is
    /// generous: a build alongside the rest of the suite has taken ~2 s.
    @MainActor
    @Test("building a stack off the main thread doesn't wait on main")
    func buildsWithoutMainThread() {
        let built = DispatchSemaphore(value: 0)
        Thread {
            _ = CoreDataStack(inMemory: true)
            built.signal()
        }.start()
        #expect(built.wait(timeout: .now() + 30) == .success)
    }
}
