import Foundation
import Testing
@testable import Cyclometer

/// #583: the ride-end marker file holds one marker per ride, and still reads the single
/// marker it held before. #607: and each marker's summary, when it can.
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

    /// #607: a marker carries Finish's summary through the file and back.
    @Test("A marker's summary survives the file")
    func summaryRoundTrips() {
        let url = Self.makeFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        var marker = Self.marker(1_000, export: "leftover")
        marker.summary = RideSummaryUpdate(
            rideId: marker.rideId, recordingState: .ended,
            durationSeconds: 3_600, distanceMeters: 30_000, averageSpeedMPS: 8.3, maxSpeedMPS: 14,
            averageHeartRateBPM: 142, cadenceSecondsByRPM: [88: 1_200],
            pauses: [RidePause(startedAt: Date(timeIntervalSince1970: 900), endedAt: nil, isAuto: false)],
            route: RouteReference(id: UUID(), name: "Lakeshore")
        )
        RideEndIntentClient.file(at: url).save(marker)

        #expect(RideEndIntentClient.file(at: url).loadAll() == [marker])
    }

    /// #607: a marker written before it has no summary, and one whose summary can't be read (a
    /// field added since) still reads, with none. Either throwing would lose every ride's marker,
    /// since the file decodes as one array.
    @Test("A marker without a readable summary still reads, with none", arguments: [nil, #"{"rideId":"x"}"#])
    func markerWithoutReadableSummaryReads(summaryJSON: String?) throws {
        let url = Self.makeFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let leftover = Self.marker(1_000, export: "leftover")
        let next = Self.marker(2_000)
        // The pre-#607 shape, written by hand so it doesn't depend on today's encoder.
        let markers = try [leftover, next].map { marker in
            var json = try #require(
                try JSONSerialization.jsonObject(with: JSONEncoder().encode(marker)) as? [String: Any]
            )
            #expect(json["summary"] == nil)
            if let summaryJSON {
                json["summary"] = try JSONSerialization.jsonObject(with: Data(summaryJSON.utf8))
            }
            return json
        }
        try JSONSerialization.data(withJSONObject: markers).write(to: url)

        #expect(RideEndIntentClient.file(at: url).loadAll() == [leftover, next])
    }

    @Test("No file reads as no markers")
    func missingFileReadsEmpty() {
        let client = RideEndIntentClient.file(at: Self.makeFileURL())
        #expect(client.loadAll().isEmpty)
        #expect(client.load(UUID()) == nil)
    }
}
