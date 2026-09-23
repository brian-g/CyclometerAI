import Foundation
import SwiftData
import Testing
@testable import Cyclometer

/// #261: deleting a ride used to remove one SwiftData row and nothing else, leaving the
/// exported GPX file visible in Files, thousands of CoreData `TrackPoint` rows on disk and
/// the ride's `VehiclePassEvent` rows behind it. Three orphaned `.gpx` files on a test
/// device are what the issue was filed from.
@Suite("PersistenceClient — deleteRide")
struct RideDeletionTests {

    /// Everything one ride owns, in a temp directory that is the test's to delete.
    private struct Fixture {
        let client: PersistenceClient
        let swiftDataStack: SwiftDataStack
        let rideId: UUID
        let directory: URL
        var fileURL: URL { directory.appendingPathComponent("Cyclometer_ride.gpx") }
    }

    /// A finalized ride with three track points, two pass events and a real file on disk.
    /// `writesFile: false` is the ride whose export failed — `gpxFileURL` stays nil.
    private static func makeRide(writesFile: Bool = true) async throws -> Fixture {
        let (client, swiftDataStack) = PersistenceClientTests.makeLiveClient()
        let rideId = UUID()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RideDeletionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fixture = Fixture(
            client: client, swiftDataStack: swiftDataStack, rideId: rideId, directory: directory
        )

        let base = Date()
        try await client.createRide(rideId, base, nil)
        try await client.flushTrackPoints((0..<3).map { offset in
            TrackPointDTO(
                rideId: rideId,
                timestamp: base.addingTimeInterval(TimeInterval(offset)),
                latitude: 36.09, longitude: -79.52,
                altitudeMeters: 200, horizontalAccuracyMeters: 5,
                speedMPS: 4, speedSource: .gps,
                heartRateBPM: nil, heartRateSource: .none,
                cadenceRPM: nil, powerWatts: nil
            )
        })
        try await client.appendVehiclePassEvents((0..<2).map { offset in
            VehiclePassEventDTO(
                rideId: rideId,
                timestamp: base.addingTimeInterval(TimeInterval(offset)),
                latitude: 36.09, longitude: -79.52,
                alertLevelAtPass: .caution, riderSpeedKph: 25, estimatedPassSpeedKph: 50
            )
        })
        if writesFile {
            try Data("<gpx/>".utf8).write(to: fixture.fileURL)
        }
        let summary = RideSummaryUpdate(
            rideId: rideId, recordingState: .ended,
            durationSeconds: 3, distanceMeters: 12, averageSpeedMPS: 4, maxSpeedMPS: 4
        )
        try await client.finalizeRide(rideId, base.addingTimeInterval(3), summary, writesFile ? fixture.fileURL : nil)

        return fixture
    }

    private static func rideExists(_ id: UUID, in stack: SwiftDataStack) throws -> Bool {
        let context = ModelContext(stack.container)
        var descriptor = FetchDescriptor<Ride>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).isEmpty == false
    }

    @Test("Deleting a ride takes its file, its track points, its pass events and its row")
    func deleteRemovesEverythingTheRideOwns() async throws {
        let fixture = try await Self.makeRide()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        #expect(FileManager.default.fileExists(atPath: fixture.fileURL.path))

        try await fixture.client.deleteRide(fixture.rideId)

        #expect(FileManager.default.fileExists(atPath: fixture.fileURL.path) == false)
        #expect(try await fixture.client.fetchTrackPoints(fixture.rideId).isEmpty)
        #expect(try await fixture.client.fetchVehiclePassEvents(fixture.rideId).isEmpty)
        #expect(try Self.rideExists(fixture.rideId, in: fixture.swiftDataStack) == false)
    }

    @Test("A ride whose export failed deletes cleanly")
    func deleteRideWithNoExportedFile() async throws {
        let fixture = try await Self.makeRide(writesFile: false)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        try await fixture.client.deleteRide(fixture.rideId)

        #expect(try await fixture.client.fetchTrackPoints(fixture.rideId).isEmpty)
        #expect(try Self.rideExists(fixture.rideId, in: fixture.swiftDataStack) == false)
    }

    @Test("A ride whose file is already gone deletes cleanly")
    func deleteRideWithAMissingFile() async throws {
        let fixture = try await Self.makeRide()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        // The rider got there first, in Files.
        try FileManager.default.removeItem(at: fixture.fileURL)

        try await fixture.client.deleteRide(fixture.rideId)

        #expect(try await fixture.client.fetchTrackPoints(fixture.rideId).isEmpty)
        #expect(try await fixture.client.fetchVehiclePassEvents(fixture.rideId).isEmpty)
        #expect(try Self.rideExists(fixture.rideId, in: fixture.swiftDataStack) == false)
    }

    @Test("Deleting one ride leaves another ride's data alone")
    func deleteIsScopedToOneRide() async throws {
        let fixture = try await Self.makeRide()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        // A second ride in the same two stores, sharing nothing but the tables.
        let otherRideId = UUID()
        let base = Date()
        try await fixture.client.createRide(otherRideId, base, nil)
        try await fixture.client.flushTrackPoints([
            TrackPointDTO(
                rideId: otherRideId, timestamp: base,
                latitude: 1, longitude: 2, altitudeMeters: 3, horizontalAccuracyMeters: 4,
                speedMPS: nil, speedSource: .none,
                heartRateBPM: nil, heartRateSource: .none,
                cadenceRPM: nil, powerWatts: nil
            )
        ])
        try await fixture.client.appendVehiclePassEvents([
            VehiclePassEventDTO(
                rideId: otherRideId, timestamp: base, latitude: 1, longitude: 2,
                alertLevelAtPass: .danger, riderSpeedKph: 30, estimatedPassSpeedKph: nil
            )
        ])

        try await fixture.client.deleteRide(fixture.rideId)

        #expect(try await fixture.client.fetchTrackPoints(otherRideId).count == 1)
        #expect(try await fixture.client.fetchVehiclePassEvents(otherRideId).count == 1)
        #expect(try Self.rideExists(otherRideId, in: fixture.swiftDataStack))
    }

    /// `deleteRide` runs on `RidePersistenceActor`'s own context, not the container's main
    /// context the app reads from elsewhere (fetches for GPX export, migration checks,
    /// etc.). Before #261 the view deleted the row itself, on the main context, so the row
    /// vanished by construction; now it has to reach the main context from another one.
    /// (The Rides tab itself reads through `PersistenceClient.fetchRides`, not a live
    /// `@Query`, since #247 — this test predates and is independent of that change.)
    ///
    /// This pins the cross-context propagation a deletion depends on — a main-context
    /// fetch no longer finds the ride.
    @Test("A delete on the actor's context is visible to the container's main context")
    func deleteIsVisibleToTheMainContext() async throws {
        let fixture = try await Self.makeRide()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let mainContext = await fixture.swiftDataStack.container.mainContext
        let descriptor = FetchDescriptor<Ride>(predicate: #Predicate { $0.endedAt != nil })
        // Fetched before the delete, so the row is one this context has already seen —
        // a context that never knew about it could report absence for the wrong reason.
        #expect(try await MainActor.run { try mainContext.fetch(descriptor) }.count == 1)

        try await fixture.client.deleteRide(fixture.rideId)

        #expect(try await MainActor.run { try mainContext.fetch(descriptor) }.isEmpty)
    }

    @Test("Deleting a ride that is already gone is not an error")
    func deleteUnknownRideIsANoop() async throws {
        let (client, _) = PersistenceClientTests.makeLiveClient()
        try await client.deleteRide(UUID())
    }
}
