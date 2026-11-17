import SwiftData
import Foundation
import os

private let logger = Logger.cyclometer(.persistence)

/// SwiftData stack — low-frequency Ride summary and VehiclePassEvent records (and,
/// later, RadarEvent / UserProfile). High-frequency time-series data lives in
/// CoreDataStack (NSBatchInsertRequest).
///
/// A store that won't open is not a crash (#206). It was a `fatalError`, so a refused
/// migration (#186), a corrupt file or a full disk became a crash before first frame on every
/// launch, and deleting the app, with all its history, was the only way out. Now the stack
/// opens an in-memory stand-in, so the app runs and can record a ride, and reports `failure`.
/// The file stays where it is: it may open again at the next launch, and only a reset the
/// rider asks for moves it aside (`PersistentStores.resetUnavailableStores`).
final class SwiftDataStack: @unchecked Sendable {
    static let shared = SwiftDataStack(
        configuration: ModelConfiguration(schema: SwiftDataStack.schema, isStoredInMemoryOnly: false, allowsSave: true)
    )

    let container: ModelContainer
    /// Why the store at `configuration.url` didn't open, or nil when it did. Non-nil means
    /// `container` is the stand-in.
    let failure: StoreFailure?
    /// What `reopened()` opens again: the store's own configuration, so a reset puts the fresh
    /// store exactly where launch looks for it.
    private let configuration: ModelConfiguration

    #if DEBUG
    /// Test-only: an isolated, ephemeral store instead of `.shared`'s. Unlike
    /// CoreDataStack's inMemory init (SQLite pointed at /dev/null, needed because
    /// NSBatchInsertRequest requires a real store type), SwiftData's own
    /// isStoredInMemoryOnly works fine here — Ride writes go through plain
    /// ModelContext.save(), not a SQL batch request.
    convenience init(inMemory: Bool) {
        self.init(configuration: ModelConfiguration(
            schema: Self.schema, isStoredInMemoryOnly: inMemory, allowsSave: true
        ))
    }

    /// Test-only: the store at `storeURL`, opened against `schema`, which a test can make one
    /// the store can't migrate to.
    convenience init(storeURL: URL, schema: Schema = SwiftDataStack.schema) {
        self.init(configuration: ModelConfiguration(schema: schema, url: storeURL, allowsSave: true), schema: schema)
    }
    #endif

    /// A container that is already open, as `PersistenceClient.live(coreDataContainer:modelContainer:)`
    /// is handed one. Nothing failed, so there is nothing to reset.
    init(container: ModelContainer) {
        self.container = container
        failure = nil
        configuration = container.configurations.first
            ?? ModelConfiguration(schema: container.schema, isStoredInMemoryOnly: true)
    }

    /// The one schema production loads. Exposed so migration tests open a store
    /// against exactly this, rather than a hand-copied model list that silently
    /// drifts the moment a model is added here.
    static let schema = Schema([Ride.self, VehiclePassEvent.self, Route.self])

    private init(configuration: ModelConfiguration, schema: Schema = SwiftDataStack.schema) {
        self.configuration = configuration
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
            failure = nil
        } catch {
            logger.fault("SwiftData store failed to open, running on an in-memory stand-in: \(String(describing: error), privacy: .public)")
            failure = StoreFailure(storeURL: configuration.url, reason: String(describing: error))
            container = Self.standIn(schema: schema)
        }
    }

    /// A fresh stack on the same configuration — after a reset has moved the failed store
    /// aside, an empty store in its place. It can fail again, on a disk still full, and then
    /// reports so.
    func reopened() -> SwiftDataStack {
        SwiftDataStack(configuration: configuration, schema: container.schema)
    }

    /// An in-memory container can't fail for any reason a store can: there is no file, no
    /// migration and no disk. Only a schema SwiftData rejects outright, which is a build that
    /// can't have passed its tests, makes this throw.
    private static func standIn(schema: Schema) -> ModelContainer {
        do {
            return try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, allowsSave: true)]
            )
        } catch {
            fatalError("SwiftData rejected its own schema: \(error)")
        }
    }
}
