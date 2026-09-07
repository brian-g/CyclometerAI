import Foundation

/// Parses GPX into inspectable values — both Cyclometer's own export, so
/// `GPXExporterTests` can assert on document *structure*, and the planned-route files
/// riders import from Komoot, RideWithGPS, Strava and OnTheGoMap (#190).
///
/// `String.contains("<gpxtpx:hr>142</gpxtpx:hr>")` cannot tell one track point from a
/// thousand, and cannot distinguish "this field is absent" from "this field is absent
/// here but present on the wrong point". Both matter: #173's acceptance criterion is
/// that a sensor field is *omitted*, not zeroed, for the seconds it has no source.
///
/// This layer stays deliberately document-shaped: it reports what the file *says*, and
/// nothing about what a route *means*. Which container supplies the geometry, and what
/// counts as a turn cue, are `GPXRouteImporter`'s decisions on top of this — so there is
/// one `XMLParser` delegate in the codebase rather than one per consumer.
///
/// `XMLDocument` is unavailable on iOS, so this is an `XMLParser` delegate. Namespace
/// processing is left off (the default), which keeps `gpxtpx:hr` and `cyc:alertLevel`
/// as literal qualified element names — the same choice, for the same reason, as
/// `RootElementCapture` in `GPXExporterTests`.
struct ParsedGPX: Equatable {
    struct TrackPoint: Equatable {
        var latitude: Double?
        var longitude: Double?
        var elevation: Double?
        var time: String?
        var heartRate: Int?
        var cadence: Int?
        var speed: Double?
    }

    /// `<rtept>` — a *planned* route's point. Unlike `<trkpt>` it routinely carries a
    /// `<name>`, which is how a Komoot `<rte>` states its turn cues: the geometry and
    /// the cue list are the same elements.
    struct RoutePoint: Equatable {
        var latitude: Double?
        var longitude: Double?
        var elevation: Double?
        var time: String?
        var name: String?
        var desc: String?
        var type: String?
    }

    struct Waypoint: Equatable {
        var latitude: Double?
        var longitude: Double?
        var time: String?
        var name: String?
        var desc: String?
        var type: String?
        var alertLevel: String?
        var riderSpeedKph: Double?
        var estimatedPassSpeedKph: Double?
    }

    var metadataName: String?
    var metadataDescription: String?
    var metadataTime: String?
    var trackName: String?
    var trackDescription: String?
    var trackType: String?
    var routeName: String?
    var routeDescription: String?
    var routeType: String?
    /// Every `<trkpt>` in document order, across every `<trkseg>` and every `<trk>`: a
    /// track split into segments is one ordered list of points, not several lists.
    var trackPoints: [TrackPoint] = []
    /// Every `<rtept>` in document order.
    var routePoints: [RoutePoint] = []
    var waypoints: [Waypoint] = []
}

/// The GPX *read* path's single error type. Document-level failures and import-level
/// refusals both surface here because they are one pipeline — `GPXParsing` feeding
/// `GPXRouteImporter` — and a caller importing a file has one thing to catch.
enum GPXImportError: Error, Equatable {
    /// The document is not well-formed. `XMLParser.parse()` returned false.
    case malformed
    /// Bigger than the caller's byte cap, refused before the bytes were read.
    case fileTooLarge
    /// More `<trkpt>`/`<rtept>` than the caller's cap. Parsing was aborted part-way
    /// rather than run to completion into an array that large.
    case tooManyPoints
    /// The URL could not be read at all.
    case unreadableFile
    /// Well-formed, but carries no `<trkpt>` and no `<rtept>` — nothing to ride.
    case noCoordinates
}

enum GPXParsing {
    /// - Parameter maximumPointCount: how many `<trkpt>`/`<rtept>` to admit before
    ///   aborting with `.tooManyPoints`. Unlimited by default, so the exporter's own
    ///   round-trip tests are unaffected by the route importer's caps.
    static func parse(_ data: Data, maximumPointCount: Int = .max) throws -> ParsedGPX {
        let parser = XMLParser(data: data)
        let delegate = Delegate(maximumPointCount: maximumPointCount)
        parser.delegate = delegate
        guard parser.parse() else {
            // abortParsing() also makes parse() return false, so the delegate's flag is
            // the only thing separating "too big" from "not well-formed".
            throw delegate.limitExceeded ? GPXImportError.tooManyPoints : GPXImportError.malformed
        }
        return delegate.result
    }

    /// Convenience for callers that already hold the document as text. Prefer the `Data`
    /// overload for anything read from disk: a GPX written by another tool declares its
    /// own encoding in the XML prolog and `XMLParser(data:)` honours it, where decoding
    /// to a UTF-8 `String` first would not.
    static func parse(_ xml: String) throws -> ParsedGPX {
        try parse(Data(xml.utf8))
    }

    /// `<name>`, `<desc>` and `<time>` each appear in several different containers
    /// (`metadata`, `wpt`, `trk`, `rte`, `rtept`), so the element name alone never
    /// identifies a field. The open-element stack supplies the missing context.
    private final class Delegate: NSObject, XMLParserDelegate {
        var result = ParsedGPX()
        private(set) var limitExceeded = false

        private let maximumPointCount: Int
        private var pointCount = 0
        private var stack: [String] = []
        private var text = ""
        private var waypoint: ParsedGPX.Waypoint?
        private var trackPoint: ParsedGPX.TrackPoint?
        private var routePoint: ParsedGPX.RoutePoint?

        init(maximumPointCount: Int) {
            self.maximumPointCount = maximumPointCount
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            stack.append(elementName)
            text = ""

            switch elementName {
            case "wpt":
                waypoint = ParsedGPX.Waypoint(
                    latitude: attributeDict["lat"].flatMap(Double.init),
                    longitude: attributeDict["lon"].flatMap(Double.init)
                )
            case "trkpt":
                guard admitPoint(parser) else { return }
                trackPoint = ParsedGPX.TrackPoint(
                    latitude: attributeDict["lat"].flatMap(Double.init),
                    longitude: attributeDict["lon"].flatMap(Double.init)
                )
            case "rtept":
                guard admitPoint(parser) else { return }
                routePoint = ParsedGPX.RoutePoint(
                    latitude: attributeDict["lat"].flatMap(Double.init),
                    longitude: attributeDict["lon"].flatMap(Double.init)
                )
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            defer {
                stack.removeLast()
                text = ""
            }

            switch elementName {
            case "wpt":
                if let waypoint { result.waypoints.append(waypoint) }
                waypoint = nil
                return
            case "trkpt":
                if let trackPoint { result.trackPoints.append(trackPoint) }
                trackPoint = nil
                return
            case "rtept":
                if let routePoint { result.routePoints.append(routePoint) }
                routePoint = nil
                return
            default:
                break
            }

            let container = stack.dropLast()

            switch elementName {
            case "name":
                if container.contains("metadata") {
                    keepFirst(&result.metadataName, value)
                } else if waypoint != nil {
                    waypoint?.name = value
                } else if routePoint != nil {
                    routePoint?.name = value
                } else if container.contains("trk") {
                    keepFirst(&result.trackName, value)
                } else if container.contains("rte") {
                    keepFirst(&result.routeName, value)
                } else if container.last == "gpx" {
                    // GPX 1.0 has no <metadata>: <name>/<desc> sit directly under <gpx>.
                    keepFirst(&result.metadataName, value)
                }
            case "desc":
                if container.contains("metadata") {
                    keepFirst(&result.metadataDescription, value)
                } else if waypoint != nil {
                    waypoint?.desc = value
                } else if routePoint != nil {
                    routePoint?.desc = value
                } else if container.contains("trk") {
                    keepFirst(&result.trackDescription, value)
                } else if container.contains("rte") {
                    keepFirst(&result.routeDescription, value)
                } else if container.last == "gpx" {
                    keepFirst(&result.metadataDescription, value)
                }
            case "time":
                if container.contains("metadata") {
                    result.metadataTime = value
                } else if waypoint != nil {
                    waypoint?.time = value
                } else if trackPoint != nil {
                    trackPoint?.time = value
                } else if routePoint != nil {
                    routePoint?.time = value
                }
            case "type":
                if waypoint != nil {
                    waypoint?.type = value
                } else if routePoint != nil {
                    routePoint?.type = value
                } else if container.contains("trk") {
                    keepFirst(&result.trackType, value)
                } else if container.contains("rte") {
                    keepFirst(&result.routeType, value)
                }
            case "ele":
                if trackPoint != nil {
                    trackPoint?.elevation = Double(value)
                } else if routePoint != nil {
                    routePoint?.elevation = Double(value)
                }
            case "gpxtpx:hr":
                trackPoint?.heartRate = Int(value)
            case "gpxtpx:cad":
                trackPoint?.cadence = Int(value)
            case "gpxtpx:speed":
                trackPoint?.speed = Double(value)
            case "cyc:alertLevel":
                waypoint?.alertLevel = value
            case "cyc:riderSpeedKph":
                waypoint?.riderSpeedKph = Double(value)
            case "cyc:estimatedPassSpeedKph":
                waypoint?.estimatedPassSpeedKph = Double(value)
            default:
                break
            }
        }

        /// Enforced here rather than after the parse: refusing a file only once its
        /// millionth point is already sitting in an array would not be a guard.
        private func admitPoint(_ parser: XMLParser) -> Bool {
            pointCount += 1
            guard pointCount > maximumPointCount else { return true }
            limitExceeded = true
            parser.abortParsing()
            return false
        }

        /// First non-empty value wins. A file with two `<trk>`s, the second unnamed, must
        /// keep the title the first one gave it rather than have it blanked.
        private func keepFirst(_ storage: inout String?, _ value: String) {
            guard storage == nil, !value.isEmpty else { return }
            storage = value
        }
    }
}
