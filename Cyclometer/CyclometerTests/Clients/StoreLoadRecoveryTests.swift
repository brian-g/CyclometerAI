import ComposableArchitecture
import CoreData
import Foundation
import SwiftData
import Testing
@testable import Cyclometer

/// A history store that won't open at launch, in a shape the current schema can't migrate
/// from: `Ride` with a non-optional attribute the stored rows have no value for, the shape
/// that made #186 a launch crash.
private enum RideSchemaWithUnfillableAttribute {
    @Model
    final class Ride {
        var id: UUID
        var addedWithNoDefault: String

        init(id: UUID, addedWithNoDefault: String) {
            self.id = id
            self.addedWithNoDefault = addedWithNoDefault
        }
    }

    static let schema = Schema([Self.Ride.self])
}

/// #206: a store that fails to open runs the app on a stand-in, not into a `fatalError`.
/// The failed file stays put until the rider resets, and no ride GPX file is ever deleted
/// because of it.
@Suite("Store load recovery")
struct StoreLoadRecoveryTests {

    // MARK: Fixtures

    /// A fresh directory, removed afterwards.
    private static func withDirectory<T>(_ body: (URL) throws -> T) throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appending(component: "StoreLoadRecovery-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        return try body(directory)
    }

    private static func withDirectory<T>(_ body: (URL) async throws -> T) async throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appending(component: "StoreLoadRecovery-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        return try await body(directory)
    }

    /// Bytes no SQLite reader accepts, at a store's URL.
    private static let corruptBytes = Data(repeating: 0x5A, count: 8_192)

    private static func writeCorruptStore(at url: URL) throws {
        try corruptBytes.write(to: url)
    }

    /// A history store with one ride, written with the current schema and closed.
    private static func writeHistoryStore(at url: URL) throws {
        let container = try openStore(at: url)
        let context = ModelContext(container)
        context.insert(Ride(id: UUID(), startedAt: Date(timeIntervalSince1970: 1_772_524_500)))
        try context.save()
    }

    /// A track store with one point, written with the app's model and closed.
    private static func writeTrackStore(at url: URL) throws {
        let stack = CoreDataStack(storeURL: url)
        try #require(stack.failure == nil)
        let context = stack.newBackgroundContext()
        try context.performAndWait {
            let entity = try #require(NSEntityDescription.entity(forEntityName: "TrackPoint", in: context))
            let point = NSManagedObject(entity: entity, insertInto: context)
            point.setValue(UUID(), forKey: "id")
            point.setValue(UUID(), forKey: "rideId")
            point.setValue(Date(timeIntervalSince1970: 1_772_524_500), forKey: "timestamp")
            point.setValue(36.0726, forKey: "latitude")
            point.setValue(-79.7920, forKey: "longitude")
            point.setValue(5.0, forKey: "horizontalAccuracyMeters")
            point.setValue(7.2, forKey: "speedMPS")
            point.setValue(SensorSource.gps.rawValue, forKey: "speedSourceRaw")
            point.setValue(Int16(-1), forKey: "heartRateBPM")
            point.setValue(SensorSource.none.rawValue, forKey: "heartRateSourceRaw")
            point.setValue(Int16(-1), forKey: "cadenceRPM")
            point.setValue(Int16(-1), forKey: "powerWatts")
            try context.save()
        }
        for store in stack.container.persistentStoreCoordinator.persistentStores {
            try stack.container.persistentStoreCoordinator.remove(store)
        }
    }

    /// The app's track model with a non-optional attribute the stored points have no value for.
    private static func unmigratableTrackModel() throws -> NSManagedObjectModel {
        let base = CoreDataStack(inMemory: true).container.managedObjectModel
        let model = try #require(base.copy() as? NSManagedObjectModel)
        let entity = try #require(model.entitiesByName["TrackPoint"])
        // Not `TrackPointMO`: the app's model already claims that class.
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        let attribute = NSAttributeDescription()
        attribute.name = "addedWithNoDefault"
        attribute.attributeType = .stringAttributeType
        attribute.isOptional = false
        entity.properties.append(attribute)
        return model
    }

    private static let exportName = "AcmeRide_2026-09-23_07-45.gpx"

    /// `Documents/` with one ride export in `Rides/`.
    private static func documentsWithExport(in directory: URL) throws -> URL {
        let documents = directory.appending(component: "Documents", directoryHint: .isDirectory)
        let rides = GPXExporter.ridesDirectory(in: documents)
        try FileManager.default.createDirectory(at: rides, withIntermediateDirectories: true)
        try Data("<gpx/>".utf8).write(to: rides.appending(component: exportName))
        return documents
    }

    private static func exportExists(in documents: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: GPXExporter.ridesDirectory(in: documents).appending(component: exportName).path(percentEncoded: false)
        )
    }

    private static func stores(
        history: SwiftDataStack,
        tracks: CoreDataStack = CoreDataStack(inMemory: true),
        in directory: URL,
        documents: URL
    ) -> PersistentStores {
        PersistentStores(
            history: history,
            tracks: tracks,
            supportDirectory: directory.appending(component: "Support", directoryHint: .isDirectory),
            documentsDirectory: documents
        )
    }

    /// The #346 sweep as `AppFeature` runs it, against this client.
    private static func sweep(_ client: PersistenceClient, documents: URL) async {
        await DocumentFolders.sweepOrphanedRideExports(documentsDirectory: documents) {
            try await client.fetchRideGPXFileNames()
        }
    }

    // MARK: SwiftData

    @Test("a corrupt history store runs on a stand-in, and the file is left in place")
    func corruptHistoryStore() throws {
        try Self.withDirectory { directory in
            let url = directory.appending(component: "default.store")
            try Self.writeCorruptStore(at: url)

            let stack = SwiftDataStack(storeURL: url)

            let failure = try #require(stack.failure)
            #expect(failure.storeURL == url)
            #expect(try Data(contentsOf: url) == Self.corruptBytes)
            // The stand-in takes writes.
            let context = ModelContext(stack.container)
            context.insert(Ride(id: UUID(), startedAt: .now))
            try context.save()
        }
    }

    @Test("a history store the schema can't migrate runs on a stand-in")
    func unmigratableHistoryStore() throws {
        try Self.withDirectory { directory in
            let url = directory.appending(component: "default.store")
            try Self.writeHistoryStore(at: url)

            let stack = SwiftDataStack(storeURL: url, schema: RideSchemaWithUnfillableAttribute.schema)

            #expect(stack.failure?.storeURL == url)
            #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        }
    }

    // MARK: CoreData

    @Test("a corrupt track store runs on a stand-in, and the file is left in place")
    func corruptTrackStore() throws {
        try Self.withDirectory { directory in
            let url = directory.appending(component: "CyclometerTimeSeries.sqlite")
            try Self.writeCorruptStore(at: url)

            let stack = CoreDataStack(storeURL: url)

            #expect(stack.failure?.storeURL == url)
            #expect(try Data(contentsOf: url) == Self.corruptBytes)
        }
    }

    @Test("a track store the model can't migrate runs on a stand-in")
    func unmigratableTrackStore() throws {
        try Self.withDirectory { directory in
            let url = directory.appending(component: "CyclometerTimeSeries.sqlite")
            try Self.writeTrackStore(at: url)

            let stack = CoreDataStack(storeURL: url, model: try Self.unmigratableTrackModel())

            #expect(stack.failure?.storeURL == url)
            #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        }
    }

    // MARK: Recording on the stand-ins

    /// The safety-relevant path: a ride starts, records and ends with both stores lost.
    @Test("a ride records end to end with both stores on stand-ins")
    func recordsOnStandIns() async throws {
        try await Self.withDirectory { directory in
            let historyURL = directory.appending(component: "default.store")
            let tracksURL = directory.appending(component: "CyclometerTimeSeries.sqlite")
            try Self.writeCorruptStore(at: historyURL)
            try Self.writeCorruptStore(at: tracksURL)
            let documents = try Self.documentsWithExport(in: directory)
            let stores = Self.stores(
                history: SwiftDataStack(storeURL: historyURL),
                tracks: CoreDataStack(storeURL: tracksURL),
                in: directory, documents: documents
            )
            let client = PersistenceClient.live(stores: stores)
            #expect(client.storeStatus().history != nil)
            #expect(client.storeStatus().tracks != nil)

            let rideId = UUID()
            let start = Date(timeIntervalSince1970: 1_772_524_500)
            try await client.createRide(rideId, start, nil)
            let point = TrackPointDTO(
                id: UUID(), rideId: rideId, timestamp: start, latitude: 36.07, longitude: -79.79,
                altitudeMeters: nil, horizontalAccuracyMeters: 5, speedMPS: 7, speedSource: .gps,
                heartRateBPM: nil, heartRateSource: .none, cadenceRPM: nil, powerWatts: nil, segmentIndex: 0
            )
            try await client.flushTrackPoints([point])
            #expect(try await client.fetchTrackPoints(rideId).count == 1)

            let export = GPXExporter.ridesDirectory(in: documents).appending(component: "AcmeRide_2026-09-23_09-00.gpx")
            try Data("<gpx/>".utf8).write(to: export)
            let summary = RideSummaryUpdate(
                rideId: rideId, recordingState: .ended,
                durationSeconds: 600, distanceMeters: 4_200, averageSpeedMPS: 7, maxSpeedMPS: 9
            )
            try await client.finalizeRide(rideId, start.addingTimeInterval(600), summary, export)
            #expect(try await client.fetchRides().map(\.id) == [rideId])

            // Its row dies with the stand-in, so its export is retained by name.
            let retained = try RetainedRideExports(
                fileURL: directory.appending(component: "Support/Preserved Stores/retained-ride-exports.json")
            ).load()
            #expect(retained.contains(export.lastPathComponent))
        }
    }

    /// A past ride's points are in the track store that didn't open. Its finish stats and Apple
    /// Health workout, worked out from the empty stand-in, would be stored for good.
    @Test("while tracks are on a stand-in, only rides with points on hand are owed backfills")
    func backfillsWaitForUnavailableTracks() async throws {
        try await Self.withDirectory { directory in
            let tracksURL = directory.appending(component: "CyclometerTimeSeries.sqlite")
            try Self.writeCorruptStore(at: tracksURL)
            let documents = try Self.documentsWithExport(in: directory)
            let client = PersistenceClient.live(stores: Self.stores(
                history: SwiftDataStack(inMemory: true),
                tracks: CoreDataStack(storeURL: tracksURL),
                in: directory, documents: documents
            ))
            #expect(client.storeStatus().tracks != nil)

            let start = Date(timeIntervalSince1970: 1_772_524_500)
            let past = UUID()
            let recorded = UUID()
            for rideId in [past, recorded] {
                try await client.createRide(rideId, start, nil)
                // No live finish stats, so the ride is owed them from its track.
                let summary = RideSummaryUpdate(
                    rideId: rideId, recordingState: .ended,
                    durationSeconds: 600, distanceMeters: 4_200, averageSpeedMPS: 7, maxSpeedMPS: 9
                )
                try await client.finalizeRide(rideId, start.addingTimeInterval(600), summary, nil)
            }
            // Only the ride recorded since launch has points on the stand-in.
            try await client.flushTrackPoints([TrackPointDTO(
                id: UUID(), rideId: recorded, timestamp: start, latitude: 36.07, longitude: -79.79,
                altitudeMeters: nil, horizontalAccuracyMeters: 5, speedMPS: 7, speedSource: .gps,
                heartRateBPM: nil, heartRateSource: .none, cadenceRPM: nil, powerWatts: nil, segmentIndex: 0
            )])

            #expect(try await client.fetchRidesOwedHealthWorkout().map(\.rideId) == [recorded])
            #expect(try await client.fetchRidesOwedFinishStats().map(\.rideId) == [recorded])
        }
    }

    // MARK: Ride GPX files are never deleted

    @Test("the launch sweep deletes nothing while history is on its stand-in")
    func sweepSkippedWhileUnavailable() async throws {
        try await Self.withDirectory { directory in
            let historyURL = directory.appending(component: "default.store")
            try Self.writeCorruptStore(at: historyURL)
            let documents = try Self.documentsWithExport(in: directory)
            let client = PersistenceClient.live(stores: Self.stores(
                history: SwiftDataStack(storeURL: historyURL), in: directory, documents: documents
            ))

            await #expect(throws: PersistenceError.storeUnavailable) {
                try await client.fetchRideGPXFileNames()
            }
            await Self.sweep(client, documents: documents)

            #expect(Self.exportExists(in: documents))
        }
    }

    @Test("a reset retains every export, so the sweep on its fresh store deletes none")
    func sweepKeepsExportsAfterReset() async throws {
        try await Self.withDirectory { directory in
            let historyURL = directory.appending(component: "default.store")
            try Self.writeCorruptStore(at: historyURL)
            let documents = try Self.documentsWithExport(in: directory)
            let client = PersistenceClient.live(stores: Self.stores(
                history: SwiftDataStack(storeURL: historyURL), in: directory, documents: documents
            ))

            let reset = try await withDependencies {
                $0.date = .constant(Date(timeIntervalSince1970: 1_794_910_500))
            } operation: {
                try await client.resetUnavailableStores()
            }
            #expect(reset.status == .available)

            #expect(try await client.fetchRideGPXFileNames().contains(Self.exportName))
            await Self.sweep(client, documents: documents)
            #expect(Self.exportExists(in: documents))
        }
    }

    @Test("an unreadable retained list stops the sweep rather than letting it run without it")
    func sweepSkippedWhenRetainedListUnreadable() async throws {
        try await Self.withDirectory { directory in
            let documents = try Self.documentsWithExport(in: directory)
            let retainedURL = directory.appending(component: "Support/Preserved Stores/retained-ride-exports.json")
            try FileManager.default.createDirectory(at: retainedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("not json".utf8).write(to: retainedURL)
            let client = PersistenceClient.live(stores: Self.stores(
                history: SwiftDataStack(inMemory: true), in: directory, documents: documents
            ))

            await Self.sweep(client, documents: documents)

            #expect(Self.exportExists(in: documents))
        }
    }

    // MARK: Reset

    @Test("a reset moves a failed history store aside under a timestamped name and opens a fresh one")
    func resetMovesHistoryAside() throws {
        try Self.withDirectory { directory in
            let url = directory.appending(component: "default.store")
            try Self.writeCorruptStore(at: url)
            try Data("wal".utf8).write(to: URL(filePath: url.path(percentEncoded: false) + "-wal"))
            // An external-storage payload, where SwiftData keeps `@Attribute(.externalStorage)` values.
            let blobs = directory.appending(component: ".default_SUPPORT/_EXTERNAL_DATA", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
            try Data("polyline".utf8).write(to: blobs.appending(component: "blob"))
            let documents = try Self.documentsWithExport(in: directory)
            let stores = Self.stores(history: SwiftDataStack(storeURL: url), in: directory, documents: documents)

            // 2026-11-17 10:15:00 UTC.
            let reset = try stores.resetUnavailableStores(now: Date(timeIntervalSince1970: 1_794_910_500))

            let preserved = directory.appending(component: "Support/Preserved Stores/default-failed-20261117-101500.store")
            #expect(reset.preservedStores.map(\.standardizedFileURL) == [preserved.standardizedFileURL])
            #expect(try Data(contentsOf: preserved) == Self.corruptBytes)
            #expect(FileManager.default.fileExists(atPath: preserved.path(percentEncoded: false) + "-wal"))
            // The payloads go with the store, under the name it now opens them by.
            let preservedBlob = directory.appending(
                component: "Support/Preserved Stores/.default-failed-20261117-101500_SUPPORT/_EXTERNAL_DATA/blob"
            )
            #expect(try Data(contentsOf: preservedBlob) == Data("polyline".utf8))
            #expect(!FileManager.default.fileExists(atPath: blobs.path(percentEncoded: false)))
            #expect(reset.status == .available)
            #expect(stores.status == .available)
            // The fresh store is where launch will look, and takes writes.
            let context = ModelContext(try openStore(at: url))
            #expect(try context.fetchCount(FetchDescriptor<Ride>()) == 0)
        }
    }

    @Test("a reset replaces only the store that failed")
    func resetLeavesOpenStoreAlone() throws {
        try Self.withDirectory { directory in
            let historyURL = directory.appending(component: "default.store")
            let tracksURL = directory.appending(component: "CyclometerTimeSeries.sqlite")
            try Self.writeHistoryStore(at: historyURL)
            try Self.writeCorruptStore(at: tracksURL)
            let documents = try Self.documentsWithExport(in: directory)
            let stores = Self.stores(
                history: SwiftDataStack(storeURL: historyURL),
                tracks: CoreDataStack(storeURL: tracksURL),
                in: directory, documents: documents
            )
            #expect(stores.status.history == nil)

            let reset = try stores.resetUnavailableStores(now: Date(timeIntervalSince1970: 1_794_910_500))

            #expect(reset.preservedStores.map(\.lastPathComponent) == ["CyclometerTimeSeries-failed-20261117-101500.sqlite"])
            #expect(reset.status == .available)
            // History kept its ride.
            #expect(try ModelContext(try openStore(at: historyURL)).fetchCount(FetchDescriptor<Ride>()) == 1)
        }
    }

    @Test("a reset with both stores open moves nothing")
    func resetWithNothingFailed() throws {
        try Self.withDirectory { directory in
            let documents = try Self.documentsWithExport(in: directory)
            let stores = Self.stores(history: SwiftDataStack(inMemory: true), in: directory, documents: documents)

            let reset = try stores.resetUnavailableStores(now: .now)

            #expect(reset == PersistentStoreReset(preservedStores: [], status: .available))
        }
    }
}
