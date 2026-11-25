import Foundation

// What `StravaClient` hands features (TCA.md §4.15, PRD §8.12). These are Cyclometer's shapes, not
// Strava's: `StravaWire` decodes Strava's JSON and maps it here, so the efforts and segments cached
// on `Ride` and `Route` (DataModel.md §3.8.1) don't change when Strava's answers do.

/// A ride to upload: its GPX (§8.7), gzipped by the client, with the name and description from S10.
struct StravaUpload: Equatable, Sendable {
    var gpx: Data
    var name: String
    var description: String?
    /// The ride's UUID, so Strava can recognise the same file uploaded twice.
    var externalID: String
}

/// The id Strava gives an upload, polled until the activity exists.
struct StravaUploadID: Hashable, Codable, Sendable, RawRepresentable {
    var rawValue: String
}

/// Where an upload stands (`GET /uploads/:id`).
enum StravaUploadStatus: Equatable, Sendable {
    /// Strava hasn't finished processing the file.
    case processing
    /// Processed into this activity.
    case ready(activityID: String)
    /// The ride is already on Strava, as this activity (often imported from Apple Health). Recorded
    /// as synced with it (PRD §8.12).
    case duplicate(activityID: String)
    /// Strava couldn't process the file, or deleted the activity. `reason` is Strava's text, for
    /// the log.
    case failed(reason: String)
}

/// One segment effort Strava matched on a ride's activity. Cached as JSON on `Ride`
/// (DataModel.md §3.8.1).
struct StravaSegmentEffort: Codable, Equatable, Sendable {
    var effortID: String
    var segmentID: String
    var name: String
    var distanceMeters: Double
    var averageGradePercent: Double
    var elapsedSeconds: Int
    /// The track point the effort starts at, which orders the list by the ride.
    var startIndex: Int
    /// 0 = uncategorized … 5 = HC. S20 lists ride-derived segments too.
    var climbCategory: Int
    /// The segment's start and end: S20 keeps a segment only when both lie within 30 m of the route.
    var startLatitude: Double
    var startLongitude: Double
    var endLatitude: Double
    var endLongitude: Double
    /// 1–3: the rider's best, second and third times on the segment.
    var prRank: Int?
    /// 1–10 on the segment's leaderboard.
    var komRank: Int?
    /// The rider's best time on the segment and its date. Strava's activity answer doesn't carry
    /// them, so `StravaClient` leaves them nil; #633 decides how they are filled.
    var bestElapsedSeconds: Int?
    var bestDate: Date?
}

/// One segment on a route from Strava (`GET /routes/:id`). Cached as JSON on `Route`
/// (DataModel.md §3.8.1).
struct StravaRouteSegment: Codable, Equatable, Sendable {
    var segmentID: String
    var name: String
    var distanceMeters: Double
    var averageGradePercent: Double
    /// 0 = uncategorized … 5 = HC.
    var climbCategory: Int
    /// Strava's route answer doesn't carry it, so `StravaClient` leaves it nil; #633 and #635
    /// decide how it is filled.
    var bestElapsedSeconds: Int?
    var bestDate: Date?
}

/// A row in the rider's Strava routes (`GET /athletes/:id/routes`).
struct StravaRouteSummary: Equatable, Sendable, Identifiable {
    var routeID: String
    var name: String
    var distanceMeters: Double
    var elevationGainMeters: Double
    /// Strava's route type and subtype, passed through: the values aren't documented, so the
    /// browser (#634) decides which are rides.
    var type: Int
    var subType: Int?
    var isPrivate: Bool
    var isStarred: Bool
    var updatedAt: Date?

    var id: String { routeID }
}

/// A route with its segments (`GET /routes/:id`).
struct StravaRouteDetail: Equatable, Sendable {
    var summary: StravaRouteSummary
    var segments: [StravaRouteSegment]
}

/// One of the rider's Strava bikes (`GET /athlete`), for gear once Multi-bike lands.
struct StravaGear: Equatable, Sendable, Identifiable {
    var gearID: String
    var name: String
    var isPrimary: Bool
    var distanceMeters: Double

    var id: String { gearID }
}

/// Why a Strava request failed. A missing or disconnected account throws `StravaAuthError`
/// instead, from the token.
enum StravaError: Error, Equatable {
    /// Strava refused the request for the app's rate limit, which every rider shares (PRD §8.12).
    /// Nothing should call Strava again before `until`.
    case rateLimited(until: Date)
    /// Strava answered 401 again after the token was refreshed: most likely the request needs a
    /// scope the rider didn't grant.
    case unauthorized
    /// Any other status outside 2xx.
    case http(status: Int)
    /// A 2xx answer that doesn't decode.
    case invalidResponse
}
