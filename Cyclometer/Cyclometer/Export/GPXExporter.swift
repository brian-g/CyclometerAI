import ComposableArchitecture
import Foundation

/// Builds and writes a ride's GPX 1.1 export file (PRD §8.7, Appendix B;
/// DataModel.md §6). `buildXML` is a pure function over already-persisted data — no
/// dependencies, no I/O — so `GPXExporterTests` can exercise the schema/omission
/// rules directly against fixtures, the same shape as `VehiclePassDetector`.
enum GPXExporter {
    @Dependency(\.persistenceClient) static var persistenceClient

    /// Fetches persisted Ride/TrackPoint/VehiclePassEvent data by rideId, builds the
    /// GPX document, and atomically writes it to `Documents/Rides/`.
    static func generate(rideId: UUID) async throws -> URL {
        // fetchTrackPoints (CoreData) is independent of the other two, which both
        // route through RidePersistenceActor and so serialize against each other
        // regardless — but letting it overlap still saves latency on a long ride's
        // thousands of 1Hz rows.
        async let ride = persistenceClient.fetchRide(rideId)
        async let trackPoints = persistenceClient.fetchTrackPoints(rideId)
        async let vehiclePassEvents = persistenceClient.fetchVehiclePassEvents(rideId)
        let xml = try await buildXML(ride: ride, trackPoints: trackPoints, vehiclePassEvents: vehiclePassEvents)
        return try await write(xml: xml, rideStartedAt: ride.startedAt)
    }

    /// Pure — no I/O, no dependencies. Document order is `metadata` → `wpt`* → `trk`,
    /// matching the GPX 1.1 element sequence and PRD Appendix B's example.
    static func buildXML(
        ride: RideExportMetadata,
        trackPoints: [TrackPointDTO],
        vehiclePassEvents: [VehiclePassEventDTO]
    ) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1"
             creator="Cyclometer iOS"
             xmlns="http://www.topografix.com/GPX/1/1"
             xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v2"
             xmlns:cyc="http://cyclometerapp.com/xmlschemas/VehicleEvent/v1"
             xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
             xsi:schemaLocation="
               http://www.topografix.com/GPX/1/1
               http://www.topografix.com/GPX/1/1/gpx.xsd
               http://www.garmin.com/xmlschemas/TrackPointExtension/v2
               http://www.garmin.com/xmlschemas/TrackPointExtensionv2.xsd">

          <metadata>
            <name>\(filenameStem(for: ride.startedAt))</name>
            <time>\(isoString(ride.startedAt))</time>
          </metadata>


        """

        for event in vehiclePassEvents {
            xml += wptXML(for: event)
        }

        xml += "  <trk>\n"
        if !ride.title.isEmpty {
            xml += "    <name>\(xmlEscape(ride.title))</name>\n"
        }
        xml += "    <trkseg>\n\n"
        for point in trackPoints {
            xml += trkptXML(for: point)
        }
        xml += "    </trkseg>\n"
        xml += "  </trk>\n"
        xml += "</gpx>\n"

        return xml
    }

    /// Atomic write + filename convention (`Cyclometer_YYYY-MM-DD_HH-mm.gpx`, under
    /// `Documents/Rides/`), with numeric-suffix collision avoidance for the rare case
    /// of two rides starting in the same calendar minute. `documentsDirectory` is
    /// overridable so tests never touch the real filesystem.
    static func write(
        xml: String,
        rideStartedAt: Date,
        documentsDirectory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    ) throws -> URL {
        let ridesDirectory = documentsDirectory.appendingPathComponent("Rides", isDirectory: true)
        try FileManager.default.createDirectory(at: ridesDirectory, withIntermediateDirectories: true)
        let url = uniqueURL(in: ridesDirectory, stem: filenameStem(for: rideStartedAt))
        try Data(xml.utf8).write(to: url, options: .atomic)
        return url
    }

    /// The unsuffixed name wins when free, preserving the documented convention for
    /// the common case. First collision gets `-1`, second `-2`, and so on.
    private static func uniqueURL(in directory: URL, stem: String) -> URL {
        var url = directory.appendingPathComponent("\(stem).gpx")
        var suffix = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(stem)-\(suffix).gpx")
            suffix += 1
        }
        return url
    }

    // MARK: - Element builders

    private static func wptXML(for event: VehiclePassEventDTO) -> String {
        var xml = "  <wpt lat=\"\(coordinate(event.latitude))\" lon=\"\(coordinate(event.longitude))\">\n"
        xml += "    <time>\(isoString(event.timestamp))</time>\n"
        xml += "    <name>Vehicle Pass</name>\n"
        xml += "    <type>vehiclePass</type>\n"
        xml += "    <extensions>\n"
        xml += "      <cyc:VehiclePassEvent>\n"
        xml += "        <cyc:alertLevel>\(alertLevelString(event.alertLevelAtPass))</cyc:alertLevel>\n"
        xml += "        <cyc:riderSpeedKph>\(decimal1(event.riderSpeedKph))</cyc:riderSpeedKph>\n"
        if let estimatedPassSpeedKph = event.estimatedPassSpeedKph {
            xml += "        <cyc:estimatedPassSpeedKph>\(decimal1(estimatedPassSpeedKph))</cyc:estimatedPassSpeedKph>\n"
        }
        xml += "      </cyc:VehiclePassEvent>\n"
        xml += "    </extensions>\n"
        xml += "  </wpt>\n\n"
        return xml
    }

    private static func trkptXML(for point: TrackPointDTO) -> String {
        var xml = "      <trkpt lat=\"\(coordinate(point.latitude))\" lon=\"\(coordinate(point.longitude))\">\n"
        xml += "        <ele>\(decimal1(point.altitudeMeters))</ele>\n"
        xml += "        <time>\(isoString(point.timestamp))</time>\n"

        if point.heartRateBPM != nil || point.cadenceRPM != nil || point.speedMPS != nil {
            xml += "        <extensions>\n"
            xml += "          <gpxtpx:TrackPointExtension>\n"
            if let hr = point.heartRateBPM {
                xml += "            <gpxtpx:hr>\(hr)</gpxtpx:hr>\n"
            }
            if let cad = point.cadenceRPM {
                xml += "            <gpxtpx:cad>\(cad)</gpxtpx:cad>\n"
            }
            if let speed = point.speedMPS {
                xml += "            <gpxtpx:speed>\(decimal1(speed))</gpxtpx:speed>\n"
            }
            xml += "          </gpxtpx:TrackPointExtension>\n"
            xml += "        </extensions>\n"
        }

        xml += "      </trkpt>\n\n"
        return xml
    }

    // MARK: - Formatting

    private static func alertLevelString(_ level: AlertLevel) -> String {
        switch level {
        case .clear: return "clear"
        case .advisory: return "advisory"
        case .caution: return "caution"
        case .danger: return "danger"
        }
    }

    private static func coordinate(_ value: Double) -> String { String(format: "%.7f", value) }
    private static func decimal1(_ value: Double) -> String { String(format: "%.1f", value) }

    private static func isoString(_ date: Date) -> String { isoFormatter.string(from: date) }

    private static func filenameStem(for date: Date) -> String {
        "Cyclometer_\(filenameFormatter.string(from: date))"
    }

    /// `&` must be escaped first — escaping it after `<`/`>`/quotes would double-escape
    /// the `&` those replacements just introduced.
    private static func xmlEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Device-local time zone — this filename is rider-facing (Files app), unlike the
    /// UTC `<time>` elements inside the document. Locale/calendar are pinned to
    /// `en_US_POSIX`/Gregorian so the literal `Cyclometer_YYYY-MM-DD_HH-mm` convention
    /// holds regardless of the device's Region/Calendar setting — an unpinned
    /// `DateFormatter` renders in whatever calendar system (Japanese, Buddhist,
    /// Islamic, Hebrew...) and digit script the device is set to.
    private static let filenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        return formatter
    }()
}
