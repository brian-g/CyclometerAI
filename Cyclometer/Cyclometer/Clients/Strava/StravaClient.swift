import ComposableArchitecture
import Foundation

/// TCA dependency for Strava's API (TCA.md §4.15, PRD §8.12). Every Strava call goes through it, so
/// reducers test against `mock` and the transport is tested against recorded answers.
///
/// The live value signs each request with `StravaAuthClient`'s token, retries once with a refreshed
/// token after a 401, and throws `StravaError.rateLimited(until:)` on a 429. A missing or
/// disconnected account throws `StravaAuthError`.
struct StravaClient: Sendable {
    /// Uploads a ride's GPX (`POST /uploads`). Strava answers before it has processed the file:
    /// poll `uploadStatus` for the activity.
    var upload: @Sendable (StravaUpload) async throws -> StravaUploadID
    /// Where an upload stands (`GET /uploads/:id`).
    var uploadStatus: @Sendable (StravaUploadID) async throws -> StravaUploadStatus
    /// The segment efforts Strava matched on an activity, in ride order.
    var segmentEfforts: @Sendable (_ activityID: String) async throws -> [StravaSegmentEffort]
    /// One page (from 1) of the rider's routes, `StravaConfig.routesPerPage` at most; an empty page
    /// is the end.
    var routes: @Sendable (_ page: Int) async throws -> [StravaRouteSummary]
    /// A route and its segments.
    var route: @Sendable (_ routeID: String) async throws -> StravaRouteDetail
    /// A route's GPX, for `GPXRouteImporter`.
    var routeGPX: @Sendable (_ routeID: String) async throws -> Data
    /// The connected athlete's name and photo, for S12.1 each time it appears. Never stored.
    var athlete: @Sendable () async throws -> StravaAthlete
    /// The rider's Strava bikes. Needs `profile:read_all`.
    var bikes: @Sendable () async throws -> [StravaGear]
    /// Sets an activity's gear, which an upload can't name.
    var setGear: @Sendable (_ activityID: String, _ gearID: String) async throws -> Void
    /// Whether an activity is still on Strava (`GET /activities/:id`), so S15 can tell one the
    /// rider deleted there (#632): false on a 404. A private activity answers 404 too without
    /// `activity:read_all`, so the caller checks only with that scope granted.
    var activityExists: @Sendable (_ activityID: String) async throws -> Bool
}

extension StravaClient: DependencyKey {
    static let liveValue: StravaClient = {
        let preferences = Shared(.appPreferences)
        return StravaAPI(
            transport: .live,
            auth: .liveValue,
            athleteID: { preferences.wrappedValue.connectedServices.first { $0.serviceType == .strava }?.athleteID },
            now: { Date() }
        ).client
    }()

    /// Not connected, like `StravaAuthClient.testValue`. Tests script what they need with `mock`.
    static let testValue = StravaClient(
        upload: { _ in throw StravaAuthError.notConnected },
        uploadStatus: { _ in throw StravaAuthError.notConnected },
        segmentEfforts: { _ in throw StravaAuthError.notConnected },
        routes: { _ in throw StravaAuthError.notConnected },
        route: { _ in throw StravaAuthError.notConnected },
        routeGPX: { _ in throw StravaAuthError.notConnected },
        athlete: { throw StravaAuthError.notConnected },
        bikes: { throw StravaAuthError.notConnected },
        setGear: { _, _ in throw StravaAuthError.notConnected },
        activityExists: { _ in throw StravaAuthError.notConnected }
    )

    static let previewValue = StravaClient.mock()
}

extension DependencyValues {
    var strava: StravaClient {
        get { self[StravaClient.self] }
        set { self[StravaClient.self] = newValue }
    }
}
