import CoreData
import Foundation

/// CoreData stack — high-frequency time-series ride data.
/// Writes via NSBatchInsertRequest for performance at 1 Hz+ sampling.
/// Separate from SwiftData to avoid mixing concerns.
final class CoreDataStack {
    static let shared = CoreDataStack()

    let container: NSPersistentContainer

    private init() {
        container = NSPersistentContainer(name: "CyclometerTimeSeries")
        Self.load(container)
    }

    #if DEBUG
    /// Test-only: an isolated, ephemeral store instead of `.shared`'s. Deliberately still
    /// SQLite-backed (pointed at /dev/null) rather than NSInMemoryStoreType —
    /// NSBatchInsertRequest runs as SQL under the hood and isn't supported on the true
    /// in-memory store type. `#if DEBUG` keeps this unreachable from a Release build, so
    /// `.shared` stays the only way to get a CoreDataStack outside of tests.
    init(inMemory: Bool) {
        container = NSPersistentContainer(name: "CyclometerTimeSeries")
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        Self.load(container)
    }
    #endif

    /// A store that will not open is a launch crash, deliberately: the alternative is a ride
    /// recording into a store that silently isn't there. What keeps that from happening on an
    /// update is `CyclometerTimeSeries.xcdatamodeld` carrying every shipped model version, so
    /// CoreData can infer the mapping between them — `shouldMigrateStoreAutomatically` and
    /// `shouldInferMappingModelAutomatically` are both on by default, which is why there is
    /// nothing to configure here. Adding or removing an attribute needs a *new* model version
    /// (#263's `segmentIndex`); changing a default value does not, since default values are
    /// not part of an entity's version hash (#211). `TimeSeriesMigrationTests` covers it.
    private static func load(_ container: NSPersistentContainer) {
        container.loadPersistentStores { _, error in
            if let error { fatalError("CoreData load failed: \(error)") }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    var viewContext: NSManagedObjectContext { container.viewContext }

    func newBackgroundContext() -> NSManagedObjectContext {
        container.newBackgroundContext()
    }
}
