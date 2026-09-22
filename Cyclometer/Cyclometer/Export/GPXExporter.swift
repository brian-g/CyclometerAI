import ComposableArchitecture
import Foundation

/// Where `GPXExporter.generate` writes files — live resolves to the real
/// `Documents/` directory; test resolves to a fresh temp directory per access
/// (a computed `var`, not `static let` — same reasoning as `RideDataBuffer.testValue`)
/// so a caller that never configured `PersistenceClient.fetchRide` to throw
/// (e.g. `.testValue`, which always succeeds) still can't write into the real
/// on-device Documents folder.
private enum GPXDocumentsDirectoryKey: DependencyKey {
    static let liveValue: URL = .documentsDirectory
    static var testValue: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "GPXExporterTests-\(UUID().uuidString)", isDirectory: true
        )
    }
}

extension DependencyValues {
    var gpxDocumentsDirectory: URL {
        get { self[GPXDocumentsDirectoryKey.self] }
        set { self[GPXDocumentsDirectoryKey.self] = newValue }
    }
}

/// Builds and writes a ride's GPX 1.1 export file (PRD §8.7, Appendix B;
/// DataModel.md §6). `buildXML` is a pure function over already-persisted data — no
/// dependencies, no I/O — so `GPXExporterTests` can exercise the schema/omission
/// rules directly against fixtures, the same shape as `VehiclePassDetector`.
enum GPXExporter {
    /// Fetches persisted Ride/TrackPoint/VehiclePassEvent data by rideId, builds the
    /// GPX document, and atomically writes it to `Documents/Rides/`.
    ///
    /// The two dependencies are resolved here rather than held in `static` properties: a
    /// `@Dependency` snapshots the values current when it is initialized, and a `static` one
    /// is initialized once per process and then keeps that snapshot for the process's life.
    /// In tests that means the first client to reach this export is retained forever, holding
    /// its `ModelContainer` open on a store file the test then deletes (#242).
    static func generate(rideId: UUID) async throws -> URL {
        @Dependency(\.persistenceClient) var persistenceClient
        @Dependency(\.gpxDocumentsDirectory) var documentsDirectory
        // fetchTrackPoints (CoreData) is independent of the other two, which both
        // route through RidePersistenceActor and so serialize against each other
        // regardless — but letting it overlap still saves latency on a long ride's
        // thousands of 1Hz rows.
        async let ride = persistenceClient.fetchRide(rideId)
        async let trackPoints = persistenceClient.fetchTrackPoints(rideId)
        async let vehiclePassEvents = persistenceClient.fetchVehiclePassEvents(rideId)
        let xml = try await buildXML(ride: ride, trackPoints: trackPoints, vehiclePassEvents: vehiclePassEvents)
        return try await write(xml: xml, rideStartedAt: ride.startedAt, documentsDirectory: documentsDirectory)
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
        // One `<trkseg>` per continuous stretch of riding, so a pause is a break in the
        // track rather than a straight chord across it (#263). Readers that take a single
        // `<trkseg>` as continuous travel — Strava, Garmin Connect — then see the stop.
        for segment in segments(of: trackPoints) {
            xml += "    <trkseg>\n\n"
            for point in segment {
                xml += trkptXML(for: point)
            }
            xml += "    </trkseg>\n"
        }
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
        documentsDirectory: URL = .documentsDirectory
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

    /// Splits track points into runs of equal `segmentIndex` (#263).
    ///
    /// Consecutive runs, not a group-by: the points arrive ascending by timestamp, so a
    /// change of index is a boundary, and grouping by value would reorder the ride if an
    /// index ever repeated. Always returns at least one segment, so a ride that recorded
    /// no points still writes the one empty `<trkseg>` it always has.
    private static func segments(of trackPoints: [TrackPointDTO]) -> [[TrackPointDTO]] {
        var segments: [[TrackPointDTO]] = [[]]
        for point in trackPoints {
            if let previous = segments[segments.count - 1].last,
               previous.segmentIndex != point.segmentIndex {
                segments.append([])
            }
            segments[segments.count - 1].append(point)
        }
        return segments
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

        let hasBiometrics =
            point.heartRateBPM != nil || point.cadenceRPM != nil || point.speedMPS != nil
        // 0 is `TrackPointDTO`'s "never set" default, and CoreLocation reports a negative
        // accuracy for an invalid fix — neither is a measurement worth exporting.
        let hasAccuracy = point.horizontalAccuracyMeters > 0

        if hasBiometrics || hasAccuracy {
            xml += "        <extensions>\n"
        }
        // Metres, so *not* <hdop>: that element is dilution of precision, a unitless
        // geometry factor, and writing metres into it would be quietly wrong. A `cyc:`
        // element instead, in the namespace already declared for VehiclePassEvent (#210).
        if hasAccuracy {
            xml += "          <cyc:horizontalAccuracyMeters>"
            xml += "\(decimal1(point.horizontalAccuracyMeters))"
            xml += "</cyc:horizontalAccuracyMeters>\n"
        }
        if hasBiometrics {
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
        }
        if hasBiometrics || hasAccuracy {
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
