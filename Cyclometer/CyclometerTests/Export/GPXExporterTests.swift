import Foundation
import Testing
@testable import Cyclometer

/// Captures the root element's attributes to check namespace declarations without a
/// full schema validator — `XMLDocument` isn't available on iOS, so `XMLParser` (with
/// default `shouldProcessNamespaces = false`, which keeps `xmlns:*` as literal
/// attributes) is the well-formedness check available here.
private final class RootElementCapture: NSObject, XMLParserDelegate {
    var rootAttributes: [String: String]?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if rootAttributes == nil {
            rootAttributes = attributeDict
        }
    }
}

@Suite("GPXExporter")
struct GPXExporterTests {
    private static let start = Date(timeIntervalSince1970: 1_772_524_500)
    private static let rideId = UUID()
    private static let ride = RideExportMetadata(title: "Morning Ride", startedAt: start)

    private static func point(
        lat: Double = 36.0726, lon: Double = -79.7920, ele: Double = 220.1,
        time: Date = start,
        speedMPS: Double? = 7.2, speedSource: SensorSource = .gps,
        hr: Int? = 142, hrSource: SensorSource = .bleHR,
        cad: Int? = 85
    ) -> TrackPointDTO {
        TrackPointDTO(
            rideId: rideId, timestamp: time, latitude: lat, longitude: lon,
            altitudeMeters: ele, horizontalAccuracyMeters: 5,
            speedMPS: speedMPS, speedSource: speedSource,
            heartRateBPM: hr, heartRateSource: hrSource,
            cadenceRPM: cad, powerWatts: nil
        )
    }

    private static func passEvent(
        lat: Double = 36.0726, lon: Double = -79.7920, time: Date = start,
        alertLevel: AlertLevel = .caution, riderSpeedKph: Double = 28.4,
        estimatedPassSpeedKph: Double? = 62.1
    ) -> VehiclePassEventDTO {
        VehiclePassEventDTO(
            rideId: rideId, timestamp: time, latitude: lat, longitude: lon,
            alertLevelAtPass: alertLevel, riderSpeedKph: riderSpeedKph,
            estimatedPassSpeedKph: estimatedPassSpeedKph
        )
    }

    // MARK: - Schema / namespaces / document order

    @Test("buildXML produces well-formed XML with gpx/gpxtpx/cyc namespaces declared on the root element")
    func namespacesDeclaredOnRoot() throws {
        let xml = GPXExporter.buildXML(ride: Self.ride, trackPoints: [Self.point()], vehiclePassEvents: [Self.passEvent()])

        let parser = XMLParser(data: Data(xml.utf8))
        let capture = RootElementCapture()
        parser.delegate = capture
        #expect(parser.parse())

        let attrs = try #require(capture.rootAttributes)
        #expect(attrs["xmlns"] == "http://www.topografix.com/GPX/1/1")
        #expect(attrs["xmlns:gpxtpx"] == "http://www.garmin.com/xmlschemas/TrackPointExtension/v2")
        #expect(attrs["xmlns:cyc"] == "http://cyclometerapp.com/xmlschemas/VehicleEvent/v1")
    }

    @Test("vehicle pass waypoints appear before the track, per GPX 1.1 element order")
    func wptBeforeTrk() throws {
        let xml = GPXExporter.buildXML(ride: Self.ride, trackPoints: [Self.point()], vehiclePassEvents: [Self.passEvent()])
        let wptRange = try #require(xml.range(of: "<wpt "))
        let trkRange = try #require(xml.range(of: "<trk>"))
        #expect(wptRange.lowerBound < trkRange.lowerBound)
    }

    // MARK: - trkpt sensor field omission (absent, not zero)

    @Test("trkpt includes gpxtpx:hr/cad/speed when present, with correct values and units")
    func trkptIncludesPresentSensorFields() {
        let xml = GPXExporter.buildXML(ride: Self.ride, trackPoints: [Self.point(speedMPS: 7.2, hr: 142, cad: 85)], vehiclePassEvents: [])
        #expect(xml.contains("<gpxtpx:hr>142</gpxtpx:hr>"))
        #expect(xml.contains("<gpxtpx:cad>85</gpxtpx:cad>"))
        #expect(xml.contains("<gpxtpx:speed>7.2</gpxtpx:speed>"))
    }

    @Test("trkpt omits gpxtpx:hr/cad/speed and the whole extensions block when all three are nil")
    func trkptOmitsAllSensorFieldsAndExtensions() {
        let xml = GPXExporter.buildXML(
            ride: Self.ride,
            trackPoints: [Self.point(speedMPS: nil, speedSource: .none, hr: nil, hrSource: .none, cad: nil)],
            vehiclePassEvents: []
        )
        #expect(!xml.contains("gpxtpx:hr"))
        #expect(!xml.contains("gpxtpx:cad"))
        #expect(!xml.contains("gpxtpx:speed"))
        #expect(!xml.contains("<extensions>"))
    }

    @Test("trkpt includes only the sensor fields that are present, omitting the rest")
    func trkptOmitsOnlyMissingFields() {
        let xml = GPXExporter.buildXML(
            ride: Self.ride,
            trackPoints: [Self.point(speedMPS: nil, speedSource: .none, hr: nil, hrSource: .none, cad: 85)],
            vehiclePassEvents: []
        )
        #expect(xml.contains("<gpxtpx:cad>85</gpxtpx:cad>"))
        #expect(!xml.contains("gpxtpx:hr"))
        #expect(!xml.contains("gpxtpx:speed"))
    }

    // MARK: - wpt (vehicle pass) shape

    @Test("wpt shape matches PRD Appendix B: lat/lon attrs, time, name, type")
    func wptElementShape() {
        let xml = GPXExporter.buildXML(ride: Self.ride, trackPoints: [], vehiclePassEvents: [Self.passEvent()])
        #expect(xml.contains(#"<wpt lat="36.0726000" lon="-79.7920000">"#))
        #expect(xml.contains("<name>Vehicle Pass</name>"))
        #expect(xml.contains("<type>vehiclePass</type>"))
    }

    @Test("wpt renders every AlertLevel case as its lowercase cyc:alertLevel string")
    func alertLevelStrings() {
        let expected: [AlertLevel: String] = [.clear: "clear", .advisory: "advisory", .caution: "caution", .danger: "danger"]
        for (level, string) in expected {
            let xml = GPXExporter.buildXML(ride: Self.ride, trackPoints: [], vehiclePassEvents: [Self.passEvent(alertLevel: level)])
            #expect(xml.contains("<cyc:alertLevel>\(string)</cyc:alertLevel>"))
        }
    }

    @Test("wpt omits cyc:estimatedPassSpeedKph when nil, includes it when present")
    func estimatedPassSpeedOmission() {
        let withEstimate = GPXExporter.buildXML(ride: Self.ride, trackPoints: [], vehiclePassEvents: [Self.passEvent(estimatedPassSpeedKph: 62.1)])
        #expect(withEstimate.contains("<cyc:estimatedPassSpeedKph>62.1</cyc:estimatedPassSpeedKph>"))

        let withoutEstimate = GPXExporter.buildXML(ride: Self.ride, trackPoints: [], vehiclePassEvents: [Self.passEvent(estimatedPassSpeedKph: nil)])
        #expect(!withoutEstimate.contains("cyc:estimatedPassSpeedKph"))
        #expect(withoutEstimate.contains("<cyc:riderSpeedKph>28.4</cyc:riderSpeedKph>"))
    }

    // MARK: - trk name

    @Test("trk name is the XML-escaped ride title when present")
    func trkNameEscaped() {
        let titled = RideExportMetadata(title: "Ride <A> & \"B\"", startedAt: Self.start)
        let xml = GPXExporter.buildXML(ride: titled, trackPoints: [], vehiclePassEvents: [])
        #expect(xml.contains("<name>Ride &lt;A&gt; &amp; &quot;B&quot;</name>"))
    }

    @Test("trk omits <name> entirely when ride title is empty")
    func trkNameOmittedWhenTitleEmpty() throws {
        let untitled = RideExportMetadata(title: "", startedAt: Self.start)
        let xml = GPXExporter.buildXML(ride: untitled, trackPoints: [], vehiclePassEvents: [])
        let trkRange = try #require(xml.range(of: "<trk>"))
        #expect(!xml[trkRange.lowerBound...].contains("<name>"))
    }

    // MARK: - write (atomic, filename convention)

    @Test("write creates Documents/Rides/ and names the file by the ride's local start time")
    func writeCreatesFileWithConventionalName() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let url = try GPXExporter.write(xml: "<gpx/>", rideStartedAt: Self.start, documentsDirectory: tempDir)

        // Self.filenameStem pins en_US_POSIX + Gregorian, as GPXExporter's own
        // formatter does. An unpinned DateFormatter here would adopt the device's
        // calendar exactly as the code under test does, so the two would drift
        // together and this assertion could never fail for the reason it exists.
        let expectedName = "\(Self.filenameStem(for: Self.start)).gpx"

        #expect(url.lastPathComponent == expectedName)
        #expect(url.deletingLastPathComponent().lastPathComponent == "Rides")
        #expect(try String(contentsOf: url, encoding: .utf8) == "<gpx/>")
    }

    @Test("repeated writes for the same ride start avoid collisions with a numeric suffix: -1, -2, ...")
    func writeAvoidsCollisionsWithNumericSuffix() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = try GPXExporter.write(xml: "<gpx>first</gpx>", rideStartedAt: Self.start, documentsDirectory: tempDir)
        let secondURL = try GPXExporter.write(xml: "<gpx>second</gpx>", rideStartedAt: Self.start, documentsDirectory: tempDir)
        let thirdURL = try GPXExporter.write(xml: "<gpx>third</gpx>", rideStartedAt: Self.start, documentsDirectory: tempDir)

        let stem = firstURL.deletingPathExtension().lastPathComponent
        #expect(firstURL.lastPathComponent == "\(stem).gpx")
        #expect(secondURL.lastPathComponent == "\(stem)-1.gpx")
        #expect(thirdURL.lastPathComponent == "\(stem)-2.gpx")

        #expect(try String(contentsOf: firstURL, encoding: .utf8) == "<gpx>first</gpx>")
        #expect(try String(contentsOf: secondURL, encoding: .utf8) == "<gpx>second</gpx>")
        #expect(try String(contentsOf: thirdURL, encoding: .utf8) == "<gpx>third</gpx>")
    }

    // MARK: - Round-trip (parse the emitted document back)

    /// ISO-8601 as `GPXExporter` emits it, rebuilt independently here so the test
    /// pins the wire format rather than echoing whatever the exporter produced.
    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// Pinned to `en_US_POSIX` + Gregorian, matching `GPXExporter.filenameStem`'s own
    /// pinning. An unpinned formatter here would drift in lockstep with the code under
    /// a Buddhist/Japanese device calendar, so the assertion could never fail.
    private static func filenameStem(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        return "Cyclometer_\(formatter.string(from: date))"
    }

    @Test("round-trip: a synthetic multi-sensor ride parses back with matching point and waypoint counts and per-point field presence")
    func roundTripPreservesCountsAndPerPointFields() throws {
        // Deliberately mixed sensor coverage: every combination of present/absent that
        // the omission rule has to get right, on three points that must stay distinct
        // through the round trip. Values are chosen to survive the exporter's %.1f /
        // %.7f formatting exactly, so equality is exact rather than tolerance-based.
        let points = [
            Self.point(lat: 36.0726, lon: -79.7920, ele: 220.1, time: Self.start,
                       speedMPS: 7.2, speedSource: .gps, hr: 142, hrSource: .bleHR, cad: 85),
            Self.point(lat: 36.0727, lon: -79.7921, ele: 220.5, time: Self.start.addingTimeInterval(1),
                       speedMPS: 7.4, speedSource: .gps, hr: nil, hrSource: .none, cad: 88),
            Self.point(lat: 36.0728, lon: -79.7922, ele: 221.0, time: Self.start.addingTimeInterval(2),
                       speedMPS: nil, speedSource: .none, hr: 150, hrSource: .bleHR, cad: nil),
        ]
        let events = [
            Self.passEvent(lat: 36.0727, lon: -79.7921, time: Self.start.addingTimeInterval(1),
                           alertLevel: .caution, riderSpeedKph: 28.4, estimatedPassSpeedKph: 62.1),
            Self.passEvent(lat: 36.0728, lon: -79.7922, time: Self.start.addingTimeInterval(2),
                           alertLevel: .danger, riderSpeedKph: 30.0, estimatedPassSpeedKph: nil),
        ]

        let parsed = try GPXParsing.parse(
            GPXExporter.buildXML(ride: Self.ride, trackPoints: points, vehiclePassEvents: events)
        )

        // Counts: the assertion substring matching structurally cannot make.
        #expect(parsed.trackPoints.count == 3)
        #expect(parsed.waypoints.count == 2)

        // Every track point round-trips in order, with its own coordinates and time.
        for (index, expected) in points.enumerated() {
            let actual = parsed.trackPoints[index]
            #expect(actual.latitude == expected.latitude)
            #expect(actual.longitude == expected.longitude)
            #expect(actual.elevation == expected.altitudeMeters)
            #expect(actual.time == Self.iso(expected.timestamp))
        }

        // Per-point sensor presence — absent means nil, never 0, and a present field
        // must land on the point that actually has it.
        #expect(parsed.trackPoints[0].heartRate == 142)
        #expect(parsed.trackPoints[0].cadence == 85)
        #expect(parsed.trackPoints[0].speed == 7.2)

        #expect(parsed.trackPoints[1].heartRate == nil)
        #expect(parsed.trackPoints[1].cadence == 88)
        #expect(parsed.trackPoints[1].speed == 7.4)

        #expect(parsed.trackPoints[2].heartRate == 150)
        #expect(parsed.trackPoints[2].cadence == nil)
        #expect(parsed.trackPoints[2].speed == nil)

        // Waypoints, in order, with the estimated speed present on one and absent on
        // the other.
        for (index, expected) in events.enumerated() {
            let actual = parsed.waypoints[index]
            #expect(actual.latitude == expected.latitude)
            #expect(actual.longitude == expected.longitude)
            #expect(actual.time == Self.iso(expected.timestamp))
            #expect(actual.name == "Vehicle Pass")
            #expect(actual.type == "vehiclePass")
            #expect(actual.riderSpeedKph == expected.riderSpeedKph)
            #expect(actual.estimatedPassSpeedKph == expected.estimatedPassSpeedKph)
        }
        #expect(parsed.waypoints[0].alertLevel == "caution")
        #expect(parsed.waypoints[1].alertLevel == "danger")

        #expect(parsed.trackName == "Morning Ride")
    }

    @Test("metadata carries the filename stem as <name> and the ride start as an ISO-8601 <time>")
    func metadataNameAndTime() throws {
        let parsed = try GPXParsing.parse(
            GPXExporter.buildXML(ride: Self.ride, trackPoints: [Self.point()], vehiclePassEvents: [])
        )

        #expect(parsed.metadataName == Self.filenameStem(for: Self.start))
        #expect(parsed.metadataTime == Self.iso(Self.start))
    }

    @Test("an empty ride still emits a well-formed document with no track points and no waypoints")
    func emptyRideIsStillWellFormed() throws {
        let parsed = try GPXParsing.parse(
            GPXExporter.buildXML(ride: Self.ride, trackPoints: [], vehiclePassEvents: [])
        )

        #expect(parsed.trackPoints.isEmpty)
        #expect(parsed.waypoints.isEmpty)
        #expect(parsed.metadataName == Self.filenameStem(for: Self.start))
    }
}
