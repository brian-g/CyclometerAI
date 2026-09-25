import Foundation
import SwiftData
import Testing
@testable import Cyclometer

/// #286: the GPX is written at ride end, before S10 names the ride, so its `<trk><name>` was
/// always empty — a rename reached SwiftData and never the file riders share or upload.
@Suite("PersistenceClient — renameRide GPX")
struct RideRenameTests {

    private struct Fixture {
        let client: PersistenceClient
        let swiftDataStack: SwiftDataStack
        let rideId: UUID
        let directory: URL
        var fileURL: URL { directory.appendingPathComponent("Cyclometer_ride.gpx") }
    }

    /// A finalized ride with a real export on disk: built by `GPXExporter.buildXML` from the
    /// client's own reads, the same inputs the rewrite reads back.
    private static func makeRide() async throws -> Fixture {
        let (client, swiftDataStack) = PersistenceClientTests.makeLiveClient()
        let rideId = UUID()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RideRenameTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fixture = Fixture(
            client: client, swiftDataStack: swiftDataStack, rideId: rideId, directory: directory
        )

        let base = Date(timeIntervalSince1970: 1_790_000_000)
        try await client.createRide(rideId, base, nil)
        try await client.flushTrackPoints((0..<3).map { offset in
            TrackPointDTO(
                rideId: rideId,
                timestamp: base.addingTimeInterval(TimeInterval(offset)),
                latitude: 36.09, longitude: -79.52,
                altitudeMeters: 200, horizontalAccuracyMeters: 5,
                speedMPS: 4, speedSource: .gps,
                heartRateBPM: 140, heartRateSource: .bleHR,
                cadenceRPM: 85, powerWatts: nil
            )
        })
        try await client.appendVehiclePassEvents([
            VehiclePassEventDTO(
                rideId: rideId, timestamp: base.addingTimeInterval(1),
                latitude: 36.09, longitude: -79.52,
                alertLevelAtPass: .caution, riderSpeedKph: 25, estimatedPassSpeedKph: 50
            )
        ])
        let xml = try await GPXExporter.buildXML(
            ride: client.fetchRide(rideId),
            trackPoints: client.fetchTrackPoints(rideId),
            vehiclePassEvents: client.fetchVehiclePassEvents(rideId)
        )
        try Data(xml.utf8).write(to: fixture.fileURL)
        let summary = RideSummaryUpdate(
            rideId: rideId, recordingState: .ended,
            durationSeconds: 3, distanceMeters: 12, averageSpeedMPS: 4, maxSpeedMPS: 4
        )
        try await client.finalizeRide(rideId, base.addingTimeInterval(3), summary, fixture.fileURL)
        return fixture
    }

    private static func storedRide(_ id: UUID, in stack: SwiftDataStack) throws -> Ride {
        let context = ModelContext(stack.container)
        var descriptor = FetchDescriptor<Ride>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try #require(try context.fetch(descriptor).first)
    }

    private static func contents(of url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    /// The file with its track-name line taken out — what it must equal, byte for byte,
    /// before the rename, since the name is the only thing a rename may change.
    private static func withoutTrackName(_ xml: String) -> String {
        // Anchored on `<trk>`: `<metadata>` has a `<name>` of its own at the same indent.
        xml.replacingOccurrences(
            of: #"  <trk>\n    <name>[^\n]*</name>\n"#, with: "  <trk>\n", options: .regularExpression
        )
    }

    @Test("A rename rewrites the track name in place and changes nothing else")
    func renameRewritesTrackName() async throws {
        let fixture = try await Self.makeRide()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let original = try Self.contents(of: fixture.fileURL)
        #expect(try GPXParsing.parse(original).trackName == nil)

        try await fixture.client.renameRide(fixture.rideId, "Morning Loop")

        let renamed = try Self.contents(of: fixture.fileURL)
        #expect(try GPXParsing.parse(renamed).trackName == "Morning Loop")
        #expect(Self.withoutTrackName(renamed) == original)
        #expect(try Self.storedRide(fixture.rideId, in: fixture.swiftDataStack).gpxFileURL == fixture.fileURL)
    }

    @Test("A second rename replaces the name rather than adding another")
    func secondRenameReplacesName() async throws {
        let fixture = try await Self.makeRide()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let original = try Self.contents(of: fixture.fileURL)

        try await fixture.client.renameRide(fixture.rideId, "Morning Loop")
        try await fixture.client.renameRide(fixture.rideId, "Hills & Headwind")

        let renamed = try Self.contents(of: fixture.fileURL)
        #expect(try GPXParsing.parse(renamed).trackName == "Hills & Headwind")
        #expect(renamed.components(separatedBy: "<name>Hills &amp; Headwind</name>").count == 2)
        #expect(!renamed.contains("Morning Loop"))
        #expect(Self.withoutTrackName(renamed) == original)
    }

    @Test("A failed rewrite keeps the previous file, and the rename still lands")
    func failedRewriteKeepsFile() async throws {
        let fixture = try await Self.makeRide()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let original = try Self.contents(of: fixture.fileURL)
        // An atomic write needs to create its temporary file next to the target.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: fixture.directory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.directory.path)
        }

        try await fixture.client.renameRide(fixture.rideId, "Morning Loop")

        #expect(try Self.contents(of: fixture.fileURL) == original)
        #expect(try await fixture.client.fetchRide(fixture.rideId).title == "Morning Loop")
    }

    @Test("A rename doesn't bring back a file the rider deleted")
    func renameDoesNotRecreateDeletedFile() async throws {
        let fixture = try await Self.makeRide()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try FileManager.default.removeItem(at: fixture.fileURL)

        try await fixture.client.renameRide(fixture.rideId, "Morning Loop")

        #expect(FileManager.default.fileExists(atPath: fixture.fileURL.path) == false)
        #expect(try await fixture.client.fetchRide(fixture.rideId).title == "Morning Loop")
    }
}
