import CoreData
import Foundation
import os

private let logger = Logger.cyclometer(.persistence)

/// CoreData stack — high-frequency time-series ride data.
/// Writes via NSBatchInsertRequest for performance at 1 Hz+ sampling.
/// Separate from SwiftData to avoid mixing concerns.
///
/// A store that won't open is not a crash (#206), as `SwiftDataStack` explains. The stand-in
/// here is SQLite at `/dev/null` rather than `NSInMemoryStoreType`, for the reason the test
/// init gives: `NSBatchInsertRequest` runs as SQL, so a ride recorded on the stand-in still
/// records. Losing this store costs past rides their tracks, not the ride list.
final class CoreDataStack: @unchecked Sendable {
    static let shared = CoreDataStack(location: nil)

    private static let modelName = "CyclometerTimeSeries"

    /// Loaded once, for every container. A stand-in or a reset opens a second container in the
    /// same process, and two separately loaded models both claim `TrackPointMO`, which leaves
    /// CoreData unsure which entity a batch insert's objects belong to.
    private static let model: NSManagedObjectModel = NSPersistentContainer(name: modelName).managedObjectModel

    let container: NSPersistentContainer
    /// Why the store at its URL didn't open, or nil when it did. Non-nil means `container` is
    /// the stand-in.
    let failure: StoreFailure?
    /// Nil for the default location, which is where launch looks.
    private let storeURL: URL?

    #if DEBUG
    /// Test-only: an isolated, ephemeral store instead of `.shared`'s. Deliberately still
    /// SQLite-backed (pointed at /dev/null) rather than NSInMemoryStoreType —
    /// NSBatchInsertRequest runs as SQL under the hood and isn't supported on the true
    /// in-memory store type. `#if DEBUG` keeps this unreachable from a Release build, so
    /// `.shared` stays the only way to get a CoreDataStack outside of tests.
    convenience init(inMemory: Bool) {
        self.init(location: inMemory ? URL(fileURLWithPath: "/dev/null") : nil)
    }

    /// Test-only: the store at `storeURL`, opened against `model` (the app's own when nil),
    /// which a test can make one the store can't migrate to.
    convenience init(storeURL: URL, model: NSManagedObjectModel? = nil) {
        self.init(location: storeURL, model: model)
    }
    #endif

    /// A container that is already open, as `PersistenceClient.live(coreDataContainer:modelContainer:)`
    /// is handed one. Nothing failed, so there is nothing to reset.
    init(container: NSPersistentContainer) {
        self.container = container
        failure = nil
        storeURL = container.persistentStoreDescriptions.first?.url
    }

    private init(location storeURL: URL?, model: NSManagedObjectModel? = nil) {
        self.storeURL = storeURL
        let primary = Self.makeContainer(url: storeURL, model: model)
        do {
            try Self.load(primary)
            container = primary
            failure = nil
        } catch {
            logger.fault("CoreData store failed to open, running on a stand-in: \(String(describing: error), privacy: .public)")
            let failedURL = primary.persistentStoreDescriptions.first?.url
                ?? NSPersistentContainer.defaultDirectoryURL().appending(component: "\(Self.modelName).sqlite")
            failure = StoreFailure(storeURL: failedURL, reason: String(describing: error))
            container = Self.standIn(model: model)
        }
    }

    /// A fresh stack at the same location — after a reset has moved the failed store aside, an
    /// empty store in its place, on the model this one has (only a test opens another). It can
    /// fail again, and then reports so.
    func reopened() -> CoreDataStack {
        CoreDataStack(location: storeURL, model: container.managedObjectModel)
    }

    private static func makeContainer(url: URL?, model: NSManagedObjectModel?) -> NSPersistentContainer {
        let container = NSPersistentContainer(name: modelName, managedObjectModel: model ?? Self.model)
        if let url {
            container.persistentStoreDescriptions.first?.url = url
        }
        return container
    }

    /// What keeps a store opening on an update is `CyclometerTimeSeries.xcdatamodeld`
    /// carrying every shipped model version, so CoreData can infer the mapping between them —
    /// `shouldMigrateStoreAutomatically` and `shouldInferMappingModelAutomatically` are both on
    /// by default, which is why there is nothing to configure here. Adding or removing an
    /// attribute, or changing whether one is optional, needs a *new* model version (#263's
    /// `segmentIndex`, #303's optional `altitudeMeters`); changing a default value does not,
    /// since default values are not part of an entity's version hash (#211).
    /// `TimeSeriesMigrationTests` covers it. A store that still won't open throws, and the
    /// stack runs on its stand-in (#206).
    ///
    /// Synchronous: `shouldAddStoreAsynchronously` is off by default, so the handler has run
    /// by the time `loadPersistentStores` returns.
    ///
    /// Nothing configures `viewContext`, deliberately: nothing reads it — every read and write
    /// goes through a background context or a batch request — and it is a main-queue context,
    /// so each setter called off main is a `performBlockAndWait` onto main. Tests build stacks
    /// on the cooperative pool, and those waits once filled the pool while a MapKit teardown
    /// on main waited on work that needed it (#480). `CoreDataStackTests` pins this.
    private static func load(_ container: NSPersistentContainer) throws {
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
    }

    /// SQLite at `/dev/null` can't fail for any reason a store can — nothing to read, migrate
    /// or fill. Only a model CoreData rejects outright, which no build that passed its tests
    /// has, makes it throw.
    private static func standIn(model: NSManagedObjectModel?) -> NSPersistentContainer {
        let container = makeContainer(url: URL(fileURLWithPath: "/dev/null"), model: model)
        do {
            try load(container)
        } catch {
            fatalError("CoreData rejected its own model: \(error)")
        }
        return container
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        container.newBackgroundContext()
    }
}
