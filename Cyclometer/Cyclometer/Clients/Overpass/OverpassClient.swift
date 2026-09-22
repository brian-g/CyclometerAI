import ComposableArchitecture
import Foundation
import os

// Stream live: Console.app / Xcode console, filter subsystem "com.xavier.cyclometer".
private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "network")

/// TCA dependency for the OpenStreetMap Overpass API, which is where a route's surface comes
/// from (#252). The app's only network call: it sends a *planned route's* line — never a
/// recorded ride — to the public Overpass instance and gets back the ways along it (PRD §14).
struct OverpassClient: Sendable {
    /// Every highway within `RouteSurface.matchRadiusMeters` of the route, deduplicated.
    var ways: @Sendable ([RouteCoordinate]) async throws -> [OSMWay]
}

enum OverpassError: Error, Equatable {
    case http(status: Int)
    /// A 200 that is not an answer: Overpass reports a query that hit its timeout or memory
    /// limit in a `remark`, with whatever ways it had found so far. Stored, that partial list
    /// would read as a route that is mostly `.unknown`, and never be asked about again.
    case incomplete(remark: String)
    /// The inert test and preview value's answer: nothing was asked, so nothing is known.
    case unavailable
}

extension OverpassClient: DependencyKey {
    static let endpoint = URL(string: "https://overpass-api.de/api/interpreter")!

    /// The query is a line, not a box: `around` with a list of points follows the route, so a
    /// long route asks for a corridor instead of every road in its bounding box. Sampled every
    /// this many metres, which at `matchRadiusMeters` either side leaves no gap on a bend.
    static let querySpacingMeters = 50.0

    /// Points per request. About 20 km a request keeps each response to a size the public
    /// instance answers in seconds, and one request at a time is what its usage policy asks.
    static let pointsPerQuery = 400

    static let liveValue = OverpassClient { coordinates in
        var ways: [Int: OSMWay] = [:]
        for chunk in chunks(coordinates) {
            for way in try await fetch(query: query(chunk)) { ways[way.id] = way }
        }
        logger.notice("overpass returned \(ways.count, privacy: .public) ways")
        return Array(ways.values)
    }

    /// Throws rather than returning `[]`: an empty answer would be stored as a route that is
    /// entirely `.unknown` and never looked up again. Thrown, the route stays un-looked-up.
    static let testValue = OverpassClient { _ in throw OverpassError.unavailable }
    static let previewValue = testValue

    // MARK: - Request

    /// The route resampled to `querySpacingMeters` and cut into requests, each sharing its
    /// first point with the previous one's last so no stretch between them goes unasked.
    static func chunks(_ coordinates: [RouteCoordinate]) -> [[RouteCoordinate]] {
        let points = RouteGeometry.resampled(coordinates, everyMeters: querySpacingMeters).map(\.coordinate)
            + coordinates.suffix(1)
        guard points.count > 1 else { return points.isEmpty ? [] : [points] }
        return stride(from: 0, to: points.count - 1, by: pointsPerQuery).map { start in
            Array(points[start...min(start + pointsPerQuery, points.count - 1)])
        }
    }

    /// Highways only: a railway or a river beside the road would otherwise be the nearest way.
    /// Sidewalks, steps and the like come back too and are dropped on the device
    /// (`SurfaceClass.isRideable`), where the rule is testable and the query stays one line.
    static func query(_ chunk: [RouteCoordinate]) -> String {
        let line = chunk
            // `String(format:)` is POSIX: a decimal comma from the rider's locale would split
            // every coordinate in two. Five places is about a metre.
            .map { String(format: "%.5f,%.5f", $0.latitude, $0.longitude) }
            .joined(separator: ",")
        let radius = Int(RouteSurface.matchRadiusMeters)
        return "[out:json][timeout:25];way(around:\(radius),\(line))[\"highway\"];out tags geom;"
    }

    private static func fetch(query: String) async throws -> [OSMWay] {
        var request = URLRequest(url: endpoint, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // The Overpass usage policy asks every client to identify itself.
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        // Everything but letters and digits escaped: a form body gives `&`, `=` and `+` meaning.
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        request.httpBody = Data("data=\(encoded)".utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            logger.error("overpass answered \(status, privacy: .public)")
            throw OverpassError.http(status: status)
        }
        return try decode(data)
    }

    private static var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "Cyclometer/\(version) (iOS; route surface lookup)"
    }

    // MARK: - Response

    /// Overpass JSON: `{"elements": [{"type": "way", "id", "tags", "geometry": [{"lat", "lon"}]}]}`.
    /// Anything that is not a way with a usable line is skipped rather than failing the batch.
    static func decode(_ data: Data) throws -> [OSMWay] {
        struct Response: Decodable {
            struct Element: Decodable {
                struct Point: Decodable {
                    var lat: Double
                    var lon: Double
                }
                var type: String
                var id: Int
                var tags: [String: String]?
                var geometry: [Point?]?
            }
            var elements: [Element]
            var remark: String?
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        if let remark = response.remark {
            logger.error("overpass remark: \(remark, privacy: .public)")
            throw OverpassError.incomplete(remark: remark)
        }
        return response.elements.compactMap { element in
            let geometry = (element.geometry ?? []).compactMap { point in
                point.map { RouteCoordinate(latitude: $0.lat, longitude: $0.lon) }
            }
            guard element.type == "way", geometry.count > 1 else { return nil }
            return OSMWay(id: element.id, tags: element.tags ?? [:], geometry: geometry)
        }
    }
}

extension DependencyValues {
    var overpassClient: OverpassClient {
        get { self[OverpassClient.self] }
        set { self[OverpassClient.self] = newValue }
    }
}
