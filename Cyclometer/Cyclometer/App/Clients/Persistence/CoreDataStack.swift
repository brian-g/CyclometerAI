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
