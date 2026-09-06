import Foundation
import SwiftData
import Testing
@testable import Cyclometer

/// `Ride` exactly as it stood before #175 added the crash-recovery attributes —
/// the oldest on-disk shape a device in the wild can still be carrying. Kept as a
/// real `@Model` rather than a checked-in binary `.store` so it stays readable and
/// diffable; SwiftData derives the entity name from the class name, so this writes
/// a store whose `Ride` table is byte-compatible with what that build produced.
///
/// `VehiclePassEvent` is the shipping model, not a copy: it hasn't changed, and
/// including it keeps the only delta between the two schemas the five attributes
/// under test.
private enum RideSchemaBeforeSampleCounts {
    @Model
    final class Ride {
        var id: UUID
        var title: String
        var notes: String

        var startedAt: Date
        var endedAt: Date?

        var distanceMeters: Double
        var durationSeconds: TimeInterval
        var averageSpeedMPS: Double
        var maxSpeedMPS: Double
        var elevationGainMeters: Double
        var elevationDropMeters: Double

        var averageHeartRateBPM: Int?
        var maxHeartRateBPM: Int?
        var hrZoneDurations: [Int: TimeInterval]

        var averageCadenceRPM: Int?
        var maxCadenceRPM: Int?

        var radarEventCount: Int?
        var vehiclePassCount: Int?

        var routeName: String?
        var gpxFileURL: URL?

        @Attribute(.externalStorage)
        var weatherData: Data?

        @Attribute(.externalStorage)
        var syncRecordsData: Data?

        /// The shipping enum — its `String` raw values are the stored
        /// representation and are unchanged, so there is nothing to fork here.
        var recordingState: Cyclometer.Ride.RecordingState

        init(id: UUID = UUID(), startedAt: Date = .now) {
            self.id = id
            self.title = ""
            self.notes = ""
            self.startedAt = startedAt
            self.distanceMeters = 0
            self.durationSeconds = 0
            self.averageSpeedMPS = 0
            self.maxSpeedMPS = 0
            self.elevationGainMeters = 0
            self.elevationDropMeters = 0
            self.recordingState = .active
            self.hrZoneDurations = [:]
        }
    }

    static let schema = Schema([Self.Ride.self, VehiclePassEvent.self])
}

/// Regression coverage for the #186 launch crash: the five attributes #175 added
/// to `Ride` were non-optional and set only in `init`, so SwiftData emitted them
/// as mandatory-with-no-default. Lightweight migration then refused every store
/// written by an earlier build (`NSCocoaErrorDomain 134110`, "Validation error
/// missing attribute values on mandatory destination attribute"), and
/// `SwiftDataStack`'s `fatalError` turned that into a crash before first frame.
///
/// This suite fails on any future non-optional attribute added without a
/// declaration-site default, not just the original five.
@Suite("Ride schema migration")
struct RideSchemaMigrationTests {

    /// Runs `body` against a unique on-disk store URL, then removes the store and
    /// its SQLite sidecars. On disk rather than `isStoredInMemoryOnly` by
    /// necessity: an in-memory store has nothing to migrate *from*.
    private func withTemporaryStoreURL(_ body: (URL) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RideMigration-\(UUID().uuidString)")
            .appendingPathExtension("store")
        defer {
            for path in [url.path, url.path + "-wal", url.path + "-shm"] {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        try body(url)
    }

    /// Writes one `Ride` in the pre-#175 shape and closes the store. Scoped so the
    /// container deallocates — the reopen below has to be a genuine cold open.
    private func writeLegacyStore(at url: URL, rideId: UUID, startedAt: Date) throws {
        let schema = RideSchemaBeforeSampleCounts.schema
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url)]
        )
        let context = ModelContext(container)
        let ride = RideSchemaBeforeSampleCounts.Ride(id: rideId, startedAt: startedAt)
        ride.title = "Morning Ride"
        ride.distanceMeters = 32_186
        ride.durationSeconds = 4_212
        ride.averageSpeedMPS = 7.64
        ride.averageHeartRateBPM = 148
        ride.recordingState = .ended
        context.insert(ride)
        try context.save()
    }

    /// Cold-opens `url` with the schema production loads.
    private func openWithCurrentSchema(at url: URL) throws -> ModelContainer {
        try ModelContainer(
            for: SwiftDataStack.schema,
            configurations: [ModelConfiguration(schema: SwiftDataStack.schema, url: url)]
        )
    }

    @Test("a store written before #175 still opens against the current schema")
    func opensPreSampleCountStore() throws {
        let rideId = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_757_155_800)

        try withTemporaryStoreURL { url in
            try writeLegacyStore(at: url, rideId: rideId, startedAt: startedAt)

            // Threw NSCocoaErrorDomain 134110 before the declaration-site defaults.
            let container = try openWithCurrentSchema(at: url)

            let rides = try ModelContext(container).fetch(FetchDescriptor<Ride>())
            #expect(rides.count == 1)
            let ride = try #require(rides.first, "the pre-existing ride should survive migration")

            // Data written by the old build is intact...
            #expect(ride.id == rideId)
            #expect(ride.title == "Morning Ride")
            #expect(ride.startedAt == startedAt)
            #expect(ride.distanceMeters == 32_186)
            #expect(ride.durationSeconds == 4_212)
            #expect(ride.averageHeartRateBPM == 148)
            #expect(ride.recordingState == .ended)

            // ...and the attributes #175 added are backfilled with their defaults,
            // which is what a resumed ride would otherwise read as garbage.
            #expect(ride.isAutoPaused == false)
            #expect(ride.zeroSpeedSeconds == 0)
            #expect(ride.speedSampleCount == 0)
            #expect(ride.hrSampleCount == 0)
            #expect(ride.cadenceSampleCount == 0)
        }
    }

    @Test("a migrated store is writable, not just readable")
    func migratedStoreAcceptsWrites() throws {
        try withTemporaryStoreURL { url in
            try writeLegacyStore(at: url, rideId: UUID(), startedAt: .now)

            let context = try ModelContext(openWithCurrentSchema(at: url))
            let existing = try #require(context.fetch(FetchDescriptor<Ride>()).first)
            existing.cadenceSampleCount = 42

            context.insert(Ride())
            try context.save()

            let rides = try context.fetch(FetchDescriptor<Ride>())
            #expect(rides.count == 2)
            #expect(rides.contains { $0.cadenceSampleCount == 42 })
        }
    }
}
