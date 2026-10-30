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
    /// generous: alongside the rest of the suite this case has taken 1.8–7.6 s. The build runs
    /// at main's QoS because a semaphore doesn't donate priority, and every other suite is
    /// stalled on main until it finishes.
    @MainActor
    @Test("building a stack off the main thread doesn't wait on main")
    func buildsWithoutMainThread() {
        let built = DispatchSemaphore(value: 0)
        let builder = Thread {
            _ = CoreDataStack(inMemory: true)
            built.signal()
        }
        builder.qualityOfService = .userInteractive
        builder.start()
        #expect(built.wait(timeout: .now() + 30) == .success)
    }
}
