import Foundation

/// Parses emitted GPX back into inspectable values, so tests can assert on document
/// *structure* — how many `<trkpt>`s there are, and which sensor fields landed on
/// which one — rather than on substrings.
///
/// `String.contains("<gpxtpx:hr>142</gpxtpx:hr>")` cannot tell one track point from a
/// thousand, and cannot distinguish "this field is absent" from "this field is absent
/// here but present on the wrong point". Both matter: #173's acceptance criterion is
/// that a sensor field is *omitted*, not zeroed, for the seconds it has no source.
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

    struct Waypoint: Equatable {
        var latitude: Double?
        var longitude: Double?
        var time: String?
        var name: String?
        var type: String?
        var alertLevel: String?
        var riderSpeedKph: Double?
        var estimatedPassSpeedKph: Double?
    }

    var metadataName: String?
    var metadataTime: String?
    var trackName: String?
    var trackPoints: [TrackPoint] = []
    var waypoints: [Waypoint] = []
}

enum GPXParsingError: Error, Equatable {
    /// The document is not well-formed. `XMLParser.parse()` returned false.
    case malformed
}

enum GPXParsing {
    static func parse(_ xml: String) throws -> ParsedGPX {
        let parser = XMLParser(data: Data(xml.utf8))
        let delegate = Delegate()
        parser.delegate = delegate
        guard parser.parse() else { throw GPXParsingError.malformed }
        return delegate.result
    }

    /// `<name>` and `<time>` each appear in three different containers (`metadata`,
    /// `wpt`, `trk`/`trkpt`), so the element name alone never identifies a field.
    /// The open-element stack supplies the missing context.
    private final class Delegate: NSObject, XMLParserDelegate {
        var result = ParsedGPX()

        private var stack: [String] = []
        private var text = ""
        private var waypoint: ParsedGPX.Waypoint?
        private var trackPoint: ParsedGPX.TrackPoint?

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            stack.append(elementName)
            // Only leaf text is read, so discarding at every open element also
            // discards the inter-element whitespace XMLParser reports as characters.
            text = ""

            switch elementName {
            case "wpt":
                waypoint = ParsedGPX.Waypoint(
                    latitude: attributeDict["lat"].flatMap(Double.init),
                    longitude: attributeDict["lon"].flatMap(Double.init)
                )
            case "trkpt":
                trackPoint = ParsedGPX.TrackPoint(
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
            default:
                break
            }

            // `stack` still includes `elementName` itself here; the enclosing
            // container is whatever else is open.
            let container = stack.dropLast()

            switch elementName {
            case "name":
                if container.contains("metadata") {
                    result.metadataName = value
                } else if waypoint != nil {
                    waypoint?.name = value
                } else if container.contains("trk") {
                    result.trackName = value
                }
            case "time":
                if container.contains("metadata") {
                    result.metadataTime = value
                } else if waypoint != nil {
                    waypoint?.time = value
                } else if trackPoint != nil {
                    trackPoint?.time = value
                }
            case "type":
                waypoint?.type = value
            case "ele":
                trackPoint?.elevation = Double(value)
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
    }
}
