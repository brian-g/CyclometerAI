import Foundation
import Testing
@testable import Cyclometer

@Suite("GPXRouteImporter")
struct GPXRouteImporterTests {

    // MARK: - Fixtures
    //
    // Inline rather than on disk, matching GPXExporterTests: the fixture and the
    // assertion about it stay readable side by side, and the shape under test is the
    // point, not any particular file.

    /// Komoot writes a planned route as `<rte>`, naming only the points that are turns.
    private static let komootRoute = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" creator="komoot.de" xmlns="http://www.topografix.com/GPX/1/1">
      <metadata><name>Metadata Name</name></metadata>
      <rte>
        <name>Kettle Moraine Loop</name>
        <desc>Rolling gravel with two steep climbs</desc>
        <type>cycling</type>
        <rtept lat="42.9500000" lon="-88.5000000"><ele>280.0</ele><name>Start</name></rtept>
        <rtept lat="42.9510000" lon="-88.5010000"><ele>282.5</ele></rtept>
        <rtept lat="42.9520000" lon="-88.5020000"><ele>291.0</ele><name>Turn left onto County Road S</name></rtept>
        <rtept lat="42.9530000" lon="-88.5030000"><ele>288.0</ele></rtept>
      </rte>
    </gpx>
    """

    /// RideWithGPS writes the geometry as a `<trk>` and hangs turn cues off standalone
    /// `<wpt>`s, stating the direction in `<type>`.
    private static let rideWithGPSRoute = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" creator="ridewithgps.com" xmlns="http://www.topografix.com/GPX/1/1">
      <wpt lat="36.0730000" lon="-79.7930000">
        <name>Right onto Main St</name>
        <desc>at the stone bridge</desc>
        <type>Right</type>
      </wpt>
      <trk>
        <name>River Road Out and Back</name>
        <type>road cycling</type>
        <trkseg>
          <trkpt lat="36.0726000" lon="-79.7920000"><ele>220.1</ele></trkpt>
          <trkpt lat="36.0728000" lon="-79.7925000"><ele>221.4</ele></trkpt>
          <trkpt lat="36.0730000" lon="-79.7930000"><ele>223.0</ele></trkpt>
        </trkseg>
      </trk>
    </gpx>
    """

    /// A Strava route export: a bare track, no elevation, no time, no cues at all.
    private static let stravaBareTrack = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" creator="StravaGPX" xmlns="http://www.topografix.com/GPX/1/1">
      <trk>
        <name>Afternoon Ride</name>
        <trkseg>
          <trkpt lat="51.5074000" lon="-0.1278000"></trkpt>
          <trkpt lat="51.5080000" lon="-0.1290000"></trkpt>
        </trkseg>
      </trk>
    </gpx>
    """

    private static let multiSegmentTrack = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" creator="OnTheGoMap" xmlns="http://www.topografix.com/GPX/1/1">
      <trk>
        <name>Two Segments</name>
        <trkseg>
          <trkpt lat="1.0" lon="1.0"></trkpt>
          <trkpt lat="2.0" lon="2.0"></trkpt>
        </trkseg>
        <trkseg>
          <trkpt lat="3.0" lon="3.0"></trkpt>
          <trkpt lat="4.0" lon="4.0"></trkpt>
        </trkseg>
      </trk>
    </gpx>
    """

    private static let trackAndRoute = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" creator="mixed" xmlns="http://www.topografix.com/GPX/1/1">
      <rte>
        <name>Sparse Route</name>
        <rtept lat="9.0" lon="9.0"><name>Cue stated on the rte</name></rtept>
      </rte>
      <trk>
        <name>Dense Track</name>
        <trkseg>
          <trkpt lat="1.0" lon="1.0"></trkpt>
          <trkpt lat="2.0" lon="2.0"></trkpt>
        </trkseg>
      </trk>
    </gpx>
    """

    /// GPX 1.0 has no `<metadata>`: `<name>`/`<desc>` sit directly under `<gpx>`.
    private static let gpxOnePointZero = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.0" creator="OldTool" xmlns="http://www.topografix.com/GPX/1/0">
      <name>Legacy Export</name>
      <desc>Written before GPX 1.1</desc>
      <trk>
        <trkseg>
          <trkpt lat="1.0" lon="1.0"></trkpt>
        </trkseg>
      </trk>
    </gpx>
    """

    private static let unnamedTrack = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" creator="anon" xmlns="http://www.topografix.com/GPX/1/1">
      <metadata><name>Only The Metadata Names It</name></metadata>
      <trk>
        <trkseg>
          <trkpt lat="1.0" lon="1.0"></trkpt>
        </trkseg>
      </trk>
    </gpx>
    """

    private static func route(_ xml: String, maximumCoordinateCount: Int = GPXRouteImporter.maximumCoordinateCount) throws -> ImportedRoute {
        try GPXRouteImporter.route(from: Data(xml.utf8), maximumCoordinateCount: maximumCoordinateCount)
    }

    // MARK: - Source shapes

    @Test("A Komoot-style <rte> file parses to coordinates plus its named cue points")
    func komootRouteParses() throws {
        let route = try Self.route(Self.komootRoute)

        #expect(route.coordinates.map(\.latitude) == [42.95, 42.951, 42.952, 42.953])
        #expect(route.coordinates.map(\.elevationMeters) == [280.0, 282.5, 291.0, 288.0])
        // Only the two named rtepts are cues — naming every vertex would make a cue of
        // every bend in the road.
        #expect(route.cuePoints.map(\.name) == ["Start", "Turn left onto County Road S"])
        #expect(route.cuePoints.map(\.latitude) == [42.95, 42.952])
        #expect(route.name == "Kettle Moraine Loop")
        #expect(route.terrainDescription == "Rolling gravel with two steep climbs")
    }

    @Test("A RideWithGPS-style <trk> plus <wpt> cue file parses to coordinates and cues")
    func rideWithGPSRouteParses() throws {
        let route = try Self.route(Self.rideWithGPSRoute)

        #expect(route.coordinates.count == 3)
        #expect(route.coordinates.map(\.longitude) == [-79.792, -79.7925, -79.793])
        #expect(route.name == "River Road Out and Back")

        let cue = try #require(route.cuePoints.first)
        #expect(route.cuePoints.count == 1)
        #expect(cue.name == "Right onto Main St")
        #expect(cue.cueDescription == "at the stone bridge")
        // #192 reads the direction off this; losing it would force it onto geometry.
        #expect(cue.type == "Right")
    }

    @Test("A bare Strava-style <trk> with no <ele> and no cues parses with nil elevation")
    func bareTrackParses() throws {
        let route = try Self.route(Self.stravaBareTrack)

        #expect(route.coordinates.count == 2)
        #expect(route.coordinates.allSatisfy { $0.elevationMeters == nil })
        #expect(route.cuePoints.isEmpty)
        #expect(route.name == "Afternoon Ride")
    }

    @Test("Multiple <trkseg> join into one ordered coordinate list")
    func multipleSegmentsJoin() throws {
        let route = try Self.route(Self.multiSegmentTrack)

        // Not two lists, and not reordered at the segment boundary.
        #expect(route.coordinates.map(\.latitude) == [1.0, 2.0, 3.0, 4.0])
    }

    @Test("With both containers present the denser <trk> supplies the geometry, and the <rte> still supplies cues")
    func trackWinsOverRoute() throws {
        let route = try Self.route(Self.trackAndRoute)

        #expect(route.coordinates.map(\.latitude) == [1.0, 2.0])
        #expect(route.name == "Dense Track")
        #expect(route.cuePoints.map(\.name) == ["Cue stated on the rte"])
    }

    // MARK: - Title and description resolution

    @Test("An unnamed track falls back to the metadata name")
    func titleFallsBackToMetadata() throws {
        #expect(try Self.route(Self.unnamedTrack).name == "Only The Metadata Names It")
    }

    @Test("With no <desc> anywhere the terrain description falls back to <type>")
    func descriptionFallsBackToType() throws {
        #expect(try Self.route(Self.rideWithGPSRoute).terrainDescription == "road cycling")
    }

    @Test("A GPX 1.0 file, whose name and desc sit directly under <gpx>, still gets a title")
    func gpxOnePointZeroNamesTheRoute() throws {
        let route = try Self.route(Self.gpxOnePointZero)

        #expect(route.name == "Legacy Export")
        #expect(route.terrainDescription == "Written before GPX 1.1")
    }

    // MARK: - Cyclometer's own export

    @Test("A Cyclometer export re-imports as a route, and its vehiclePass waypoints are not cues")
    func cyclometerExportRoundTrips() throws {
        let start = Date(timeIntervalSince1970: 1_772_524_500)
        let rideId = UUID()
        func point(lat: Double, lon: Double) -> TrackPointDTO {
            TrackPointDTO(
                rideId: rideId, timestamp: start, latitude: lat, longitude: lon,
                altitudeMeters: 220.1, horizontalAccuracyMeters: 5,
                speedMPS: 7.2, speedSource: .gps,
                heartRateBPM: 142, heartRateSource: .bleHR,
                cadenceRPM: 85, powerWatts: nil
            )
        }
        let passEvent = VehiclePassEventDTO(
            rideId: rideId, timestamp: start, latitude: 36.0726, longitude: -79.792,
            alertLevelAtPass: .caution, riderSpeedKph: 28.4, estimatedPassSpeedKph: 62.1
        )
        let xml = GPXExporter.buildXML(
            ride: RideExportMetadata(title: "Morning Ride", startedAt: start),
            trackPoints: [point(lat: 36.0726, lon: -79.792), point(lat: 36.0728, lon: -79.7925)],
            vehiclePassEvents: [passEvent, passEvent]
        )

        let route = try Self.route(xml)

        #expect(route.coordinates.count == 2)
        #expect(route.name == "Morning Ride")
        // Two cars passed. Neither is a turn — a re-imported ride must not announce a
        // maneuver at every overtake.
        #expect(route.cuePoints.isEmpty)
    }

    // MARK: - Refusals

    @Test("Malformed XML throws rather than returning the points parsed so far")
    func malformedThrows() {
        let truncated = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1"><trk><trkseg><trkpt lat="1.0" lon="1.0"></trkpt>
        """
        #expect(throws: GPXImportError.malformed) { try Self.route(truncated) }
    }

    @Test("A well-formed file with no <trkpt> and no <rtept> is refused, not imported empty")
    func emptyDocumentThrows() {
        let empty = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1"><metadata><name>Nothing To Ride</name></metadata></gpx>
        """
        #expect(throws: GPXImportError.noCoordinates) { try Self.route(empty) }
    }

    @Test("A point count past the cap aborts the parse")
    func pointCapAborts() {
        #expect(throws: GPXImportError.tooManyPoints) {
            try Self.route(Self.multiSegmentTrack, maximumCoordinateCount: 3)
        }
        // ...and the cap is a ceiling, not a fencepost off by one.
        #expect(throws: Never.self) {
            try Self.route(Self.multiSegmentTrack, maximumCoordinateCount: 4)
        }
    }

    @Test("An oversized file is refused")
    func oversizedFileRefused() throws {
        let url = try Self.writeTemporaryFile(Self.stravaBareTrack)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: GPXImportError.fileTooLarge) {
            try GPXRouteImporter.route(contentsOf: url, maximumFileSizeBytes: 32)
        }
        #expect(throws: Never.self) {
            try GPXRouteImporter.route(contentsOf: url)
        }
    }

    @Test("A URL that cannot be read throws rather than trapping")
    func unreadableURLThrows() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).gpx")
        #expect(throws: GPXImportError.unreadableFile) {
            try GPXRouteImporter.route(contentsOf: missing)
        }
    }

    private static func writeTemporaryFile(_ xml: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GPXRouteImporterTests-\(UUID().uuidString).gpx")
        try Data(xml.utf8).write(to: url)
        return url
    }
}
