import CoreData
import Foundation
import Testing
@testable import Cyclometer

/// `CoreDataStack.load` calls `fatalError` when the store will not open, so a model change
/// that the existing store cannot migrate to is a launch crash for every rider who already
/// has ride history. #263 added `segmentIndex` to `TrackPoint`, which changes the entity's
/// version hash — hence the second model version in `CyclometerTimeSeries.xcdatamodeld`
/// rather than an edit in place (which is all #211's default-value change needed, since
/// default values are not part of the hash).
///
/// This suite writes a store with the *shipped* model and reopens it with the current one,
/// which is the migration a rider's device performs on the update.
@Suite("CyclometerTimeSeries migration")
struct TimeSeriesMigrationTests {
    private static let modelName = "CyclometerTimeSeries"

    private static func momd() throws -> URL {
        try #require(
            Bundle(for: TrackPointMO.self).url(forResource: modelName, withExtension: "momd")
        )
    }

    /// Loads one compiled version out of the `.momd`. Both versions ship inside it, which is
    /// what makes the inferred mapping possible in the first place.
    private static func model(version: String) throws -> NSManagedObjectModel {
        let url = try momd().appendingPathComponent("\(version).mom")
        return try #require(NSManagedObjectModel(contentsOf: url))
    }

    private static func container(
        model: NSManagedObjectModel?, storeURL: URL
    ) throws -> NSPersistentContainer {
        let container = model.map { NSPersistentContainer(name: modelName, managedObjectModel: $0) }
            ?? NSPersistentContainer(name: modelName)
        let description = NSPersistentStoreDescription(url: storeURL)
        // Explicit rather than relied upon: these two are what make the migration automatic,
        // and a future `CoreDataStack` that turned them off would sail past a test that
        // silently re-enabled them.
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { loadError = $1 }
        if let loadError { throw loadError }
        return container
    }

    @Test("A store written by the shipped model opens under the model segmentIndex was added to")
    func aShippedStoreMigrates() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TimeSeriesMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("\(Self.modelName).sqlite")
        let rideId = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_772_524_500)

        let shipped = try Self.container(
            model: try Self.model(version: Self.modelName), storeURL: storeURL
        )
        let context = shipped.newBackgroundContext()
        try context.performAndWait {
            let entity = try #require(NSEntityDescription.entity(forEntityName: "TrackPoint", in: context))
            let point = NSManagedObject(entity: entity, insertInto: context)
            point.setValue(UUID(), forKey: "id")
            point.setValue(rideId, forKey: "rideId")
            point.setValue(timestamp, forKey: "timestamp")
            point.setValue(36.0726, forKey: "latitude")
            point.setValue(-79.7920, forKey: "longitude")
            point.setValue(220.1, forKey: "altitudeMeters")
            point.setValue(5.0, forKey: "horizontalAccuracyMeters")
            point.setValue(7.2, forKey: "speedMPS")
            point.setValue(SensorSource.gps.rawValue, forKey: "speedSourceRaw")
            point.setValue(Int16(142), forKey: "heartRateBPM")
            point.setValue(SensorSource.bleHR.rawValue, forKey: "heartRateSourceRaw")
            point.setValue(Int16(85), forKey: "cadenceRPM")
            point.setValue(Int16(-1), forKey: "powerWatts")
            try context.save()
        }
        for store in shipped.persistentStoreCoordinator.persistentStores {
            try shipped.persistentStoreCoordinator.remove(store)
        }

        // No model argument: the same `NSPersistentContainer(name:)` the app itself builds,
        // resolving to whichever version `.xccurrentversion` names.
        let current = try Self.container(model: nil, storeURL: storeURL)
        let migratedContext = current.newBackgroundContext()
        try migratedContext.performAndWait {
            let request = NSFetchRequest<TrackPointMO>(entityName: "TrackPoint")
            let rows = try migratedContext.fetch(request)
            #expect(rows.count == 1)
            let row = try #require(rows.first)
            #expect(row.rideId == rideId)
            #expect(row.cadenceRPM == 85)
            // The ride recorded before the update has no pauses it can prove, so every one
            // of its points belongs to the first segment — the attribute's default, and the
            // one value that keeps its export exactly the single `<trkseg>` it was.
            #expect(row.segmentIndex == 0)
        }
    }
}
