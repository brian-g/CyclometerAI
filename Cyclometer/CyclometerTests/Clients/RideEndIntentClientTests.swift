import Foundation
import Testing
@testable import Cyclometer

/// #583: the ride-end marker file holds one marker per ride, and still reads the single
/// marker it held before.
@Suite("Ride-end intent store")
struct RideEndIntentClientTests {

    private static func makeFileURL() -> URL {
        FileManager.default.temporaryDirectory.appending(component: "\(UUID().uuidString).json")
    }

    private static func marker(_ seconds: TimeInterval, export: String? = nil) -> PendingRideEnd {
        PendingRideEnd(
            rideId: UUID(),
            endedAt: Date(timeIntervalSince1970: seconds),
            gpxFileURL: export.map { URL(filePath: "/Documents/Rides/\($0).gpx") }
        )
    }

    @Test("Each ride keeps its own marker, and clearing one leaves the rest")
    func markersAreKeptPerRide() throws {
        let url = Self.makeFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let client = RideEndIntentClient.file(at: url)
        let leftover = Self.marker(1_000, export: "leftover")
        let next = Self.marker(2_000)

        client.save(leftover)
        client.save(next)
        #expect(client.loadAll() == [leftover, next])

        // A second save for a ride replaces its marker in place: the Finish writes one before
        // the export and again after it.
        var nextWithExport = next
        nextWithExport.gpxFileURL = URL(filePath: "/Documents/Rides/next.gpx")
        client.save(nextWithExport)
        #expect(client.loadAll() == [leftover, nextWithExport])
        #expect(client.load(next.rideId) == nextWithExport)

        client.clear(next.rideId)
        #expect(client.loadAll() == [leftover])
        // A fresh client on the same file: what survives is on disk, not in memory.
        #expect(RideEndIntentClient.file(at: url).loadAll() == [leftover])

        client.clear(leftover.rideId)
        #expect(client.loadAll().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    @Test("A file written before #583 holding one marker is still read, and kept by the next save")
    func legacySingleMarkerFileIsRead() throws {
        let url = Self.makeFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let legacy = Self.marker(1_000, export: "leftover")
        try JSONEncoder().encode(legacy).write(to: url)
        let client = RideEndIntentClient.file(at: url)

        #expect(client.loadAll() == [legacy])
        #expect(client.load(legacy.rideId) == legacy)

        let next = Self.marker(2_000)
        client.save(next)
        #expect(client.loadAll() == [legacy, next])
    }

    @Test("No file reads as no markers")
    func missingFileReadsEmpty() {
        let client = RideEndIntentClient.file(at: Self.makeFileURL())
        #expect(client.loadAll().isEmpty)
        #expect(client.load(UUID()) == nil)
    }
}
