import Foundation
import os

// Stream live: Console.app / Xcode console, filter subsystem "xyz.acmeapps.ride".
private let logger = Logger.cyclometer(.network)

/// Strava's JSON answers (developers.strava.com/docs/reference), decoded and mapped to the domain
/// models in `StravaModels`.
///
/// Everything Strava may leave out is optional, such as `pr_rank` and `kom_rank` when the effort
/// earned none (a first effort on a segment never does). One malformed row is dropped, not the
/// whole answer.
///
/// No best time is read. Strava's reference shows `athlete_segment_stats` / `athlete_pr_effort` on
/// segments, but its real activity and route answers carry neither, even for a subscriber on a ride
/// with PRs (checked with `StravaLiveTests.answerShapes`, 2026-11-25). How S15 and S20 get one is
/// #633's decision.
enum StravaWire {
    // MARK: - Uploads

    /// The upload's id and where it stands: the answer to `POST /uploads` and `GET /uploads/:id`.
    static func upload(from data: Data) throws -> (id: StravaUploadID?, status: StravaUploadStatus) {
        let upload = try decode(Upload.self, from: data)
        let id = upload.idStr ?? upload.id.map(String.init)
        return (id.map(StravaUploadID.init(rawValue:)), status(of: upload))
    }

    private static func status(of upload: Upload) -> StravaUploadStatus {
        if let activityID = upload.activityId { return .ready(activityID: String(activityID)) }
        if let error = upload.error, !error.isEmpty {
            // "Ride.gpx duplicate of activity 21234316" in Strava's docs; matched loosely in case
            // the activity is written as a link.
            if let match = error.firstMatch(of: #/duplicate of\D*(\d+)/#) {
                return .duplicate(activityID: String(match.1))
            }
            return .failed(reason: error)
        }
        if upload.status == deletedStatus || upload.status == errorStatus {
            return .failed(reason: upload.status ?? "")
        }
        return .processing
    }

    private static let deletedStatus = "The created activity has been deleted."
    private static let errorStatus = "There was an error processing your activity."

    // MARK: - Segment efforts

    /// The efforts in `GET /activities/:id?include_all_efforts=true`, in ride order.
    static func segmentEfforts(from data: Data) throws -> [StravaSegmentEffort] {
        let activity = try decode(Activity.self, from: data)
        return (activity.segmentEfforts ?? [])
            .compactMap(\.value)
            .compactMap(effort)
            .sorted { $0.startIndex < $1.startIndex }
    }

    private static func effort(_ effort: Effort) -> StravaSegmentEffort? {
        let segment = effort.segment
        guard let start = segment.startLatlng.flatMap(Coordinate.init),
              let end = segment.endLatlng.flatMap(Coordinate.init) else {
            logger.notice("dropped Strava effort \(effort.id, privacy: .public): its segment has no start or end")
            return nil
        }
        return StravaSegmentEffort(
            effortID: String(effort.id),
            segmentID: String(segment.id),
            name: segment.name,
            distanceMeters: segment.distance ?? 0,
            averageGradePercent: segment.averageGrade ?? 0,
            elapsedSeconds: effort.elapsedTime,
            startIndex: effort.startIndex ?? 0,
            climbCategory: segment.climbCategory ?? 0,
            startLatitude: start.latitude,
            startLongitude: start.longitude,
            endLatitude: end.latitude,
            endLongitude: end.longitude,
            prRank: effort.prRank,
            komRank: effort.komRank
        )
    }

    // MARK: - Routes

    /// One page of `GET /athletes/:id/routes`.
    static func routes(from data: Data) throws -> [StravaRouteSummary] {
        try decode([Row<Route>].self, from: data).compactMap { $0.value?.summary }
    }

    /// `GET /routes/:id`.
    static func routeDetail(from data: Data) throws -> StravaRouteDetail {
        let route = try decode(Route.self, from: data)
        let segments = (route.segments ?? []).compactMap(\.value).map { segment in
            StravaRouteSegment(
                segmentID: String(segment.id),
                name: segment.name,
                distanceMeters: segment.distance ?? 0,
                averageGradePercent: segment.averageGrade ?? 0,
                climbCategory: segment.climbCategory ?? 0
            )
        }
        return StravaRouteDetail(summary: route.summary, segments: segments)
    }

    // MARK: - Gear

    /// The bikes in `GET /athlete`.
    static func bikes(from data: Data) throws -> [StravaGear] {
        (try decode(Athlete.self, from: data).bikes ?? []).compactMap(\.value).map { gear in
            StravaGear(
                gearID: gear.id,
                name: gear.name ?? "",
                isPrimary: gear.primary ?? false,
                distanceMeters: gear.distance ?? 0
            )
        }
    }

    // MARK: - Decoding

    /// Decodes a 2xx answer. A failure logs where it broke, never the body, which carries the
    /// rider's data, and throws `StravaError.invalidResponse`.
    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(type, from: data)
        } catch let error as DecodingError {
            logger.error("Strava answer didn't decode as \(String(describing: type), privacy: .public): \(error.codingPathDescription, privacy: .public)")
            throw StravaError.invalidResponse
        }
    }

    /// A Strava timestamp (`2018-02-20T18:02:13Z`); nil when it doesn't parse, rather than failing
    /// the answer.
    static func date(_ string: String?) -> Date? {
        string.flatMap { try? Date($0, strategy: .iso8601) }
    }
}

// MARK: - Strava's JSON

private extension StravaWire {
    struct Upload: Decodable {
        var id: Int64?
        var idStr: String?
        var error: String?
        var status: String?
        var activityId: Int64?
    }

    /// One row of an array answer: nil when it doesn't decode, so a malformed row is dropped
    /// alone rather than failing the answer. Logs where it broke, never the row.
    struct Row<Value: Decodable>: Decodable {
        var value: Value?

        init(from decoder: any Decoder) throws {
            do {
                value = try Value(from: decoder)
            } catch let error as DecodingError {
                logger.notice("dropped a Strava \(String(describing: Value.self), privacy: .public) row: \(error.codingPathDescription, privacy: .public)")
                value = nil
            }
        }
    }

    struct Activity: Decodable {
        var segmentEfforts: [Row<Effort>]?
    }

    struct Effort: Decodable {
        var id: Int64
        var elapsedTime: Int
        var startIndex: Int?
        var prRank: Int?
        var komRank: Int?
        var segment: Segment
    }

    struct Segment: Decodable {
        var id: Int64
        var name: String
        var distance: Double?
        var averageGrade: Double?
        var climbCategory: Int?
        var startLatlng: [Double]?
        var endLatlng: [Double]?
    }

    struct Route: Decodable {
        var id: Int64
        var idStr: String?
        var name: String
        var distance: Double?
        var elevationGain: Double?
        var type: Int?
        var subType: Int?
        var isPrivate: Bool?
        var starred: Bool?
        var updatedAt: String?
        var segments: [Row<Segment>]?

        enum CodingKeys: String, CodingKey {
            case id, idStr, name, distance, elevationGain, type, subType, starred, updatedAt, segments
            case isPrivate = "private"
        }

        var summary: StravaRouteSummary {
            StravaRouteSummary(
                routeID: idStr ?? String(id),
                name: name,
                distanceMeters: distance ?? 0,
                elevationGainMeters: elevationGain ?? 0,
                type: type ?? 0,
                subType: subType,
                isPrivate: isPrivate ?? false,
                isStarred: starred ?? false,
                updatedAt: StravaWire.date(updatedAt)
            )
        }
    }

    struct Athlete: Decodable {
        var bikes: [Row<Gear>]?
    }

    struct Gear: Decodable {
        var id: String
        var name: String?
        var primary: Bool?
        var distance: Double?
    }

    /// Strava's `[lat, lng]`; nil when it's empty, as it is for a segment without a location.
    struct Coordinate {
        var latitude: Double
        var longitude: Double

        init?(_ latlng: [Double]) {
            guard latlng.count == 2 else { return nil }
            latitude = latlng[0]
            longitude = latlng[1]
        }
    }
}

private extension DecodingError {
    /// The key path where decoding stopped, without values: the Swift names, after the snake-case
    /// conversion, e.g. `segmentEfforts.Index 3.segment.id`.
    var codingPathDescription: String {
        let path: [any CodingKey]
        switch self {
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            path = context.codingPath
        case .keyNotFound(let key, let context):
            path = context.codingPath + [key]
        @unknown default:
            return "unknown"
        }
        return path.map(\.stringValue).joined(separator: ".")
    }
}
