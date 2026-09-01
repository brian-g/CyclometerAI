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

        let expectedFormatter = DateFormatter()
        expectedFormatter.dateFormat = "yyyy-MM-dd_HH-mm"
        let expectedName = "Cyclometer_\(expectedFormatter.string(from: Self.start)).gpx"

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
}
