import CoreData
import Foundation

/// CoreData stack — high-frequency time-series ride data.
/// Writes via NSBatchInsertRequest for performance at 1 Hz+ sampling.
/// Separate from SwiftData to avoid mixing concerns.
final class CoreDataStack {
    static let shared = CoreDataStack()

    let container: NSPersistentContainer

    private init() {
        // REQUIRES: CyclometerTimeSeries.xcdatamodeld must exist in the Xcode target
        // before this stack is first accessed. Create it via File → New → Data Model,
        // name it "CyclometerTimeSeries", and add the TrackPoint entity.
        // Accessing CoreDataStack.shared without the model file will fatalError here.
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
