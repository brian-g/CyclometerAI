import Foundation
import Testing
@testable import Cyclometer

/// `StravaClient`'s decoders against Strava itself (#627). The fixtures' values are made up, and
/// their keys follow the real answers this suite printed (`answerShapes`), so this is what proves
/// the decoders still match Strava. Off unless a token is passed, so it never runs in CI. It only
/// reads, and writes and stores nothing.
///
/// Set in the shell that runs `xcodebuild test`; xcodebuild strips `TEST_RUNNER_` before the test sees it:
/// - `TEST_RUNNER_STRAVA_LIVE_TOKEN`: an access token with `read,read_all,profile:read_all,activity:read_all`
/// - `TEST_RUNNER_STRAVA_LIVE_ATHLETE_ID`: the token's athlete, for routes
/// - `TEST_RUNNER_STRAVA_LIVE_ACTIVITY_ID`, `TEST_RUNNER_STRAVA_LIVE_ROUTE_ID`: optional; their tests are skipped without them
@Suite("Strava live", .enabled(if: StravaLive.token != nil, "Set TEST_RUNNER_STRAVA_LIVE_TOKEN to check the decoders against Strava"))
struct StravaLiveTests {
    let client: StravaClient = {
        let token = StravaLive.token ?? ""
        let auth = StravaAuthClient(
            connect: { throw StravaAuthError.cancelled },
            accessToken: { token },
            // No refresh token here: the "refresh" after a 401 hands back the same token, which
            // isn't resent, so a token Strava refuses fails as `StravaError.unauthorized`.
            refreshAccessToken: { _ in token },
            disconnect: {},
            handleRedirect: { _ in false }
        )
        return StravaAPI(
            transport: .live,
            auth: auth,
            athleteID: { StravaLive.environment["STRAVA_LIVE_ATHLETE_ID"] },
            now: { Date() }
        ).client
    }()

    /// `jq -r .access_token` prints `null` when the exchange failed, and every test below then
    /// fails as unauthorized. This one names the cause.
    @Test("The token is a token, not a failed exchange")
    func tokenWasPassed() {
        #expect(
            !["", "null"].contains(StravaLive.token ?? ""),
            "STRAVA_LIVE_TOKEN is empty or \"null\": the code exchange failed, so authorize and exchange again"
        )
    }

    @Test("The athlete's bikes decode")
    func bikes() async throws {
        let bikes = try await client.bikes()
        print("strava live: \(bikes.count) bikes")
    }

    @Test("The athlete decodes")
    func athlete() async throws {
        let athlete = try await client.athlete()
        print("strava live: athlete name \(athlete.name == nil ? "absent" : "present"), photo \(athlete.photoURL == nil ? "absent" : "present")")
    }

    @Test("The first page of routes decodes; prints each route's type and subtype for #634")
    func routes() async throws {
        let routes = try await client.routes(1)
        print("strava live: \(routes.count) routes")
        for route in routes {
            print("strava live: route type \(route.type) subType \(route.subType.map(String.init) ?? "nil") — \(route.name)")
        }
    }

    @Test("A route's segments and GPX decode", .enabled(if: StravaLive.routeID != nil))
    func route() async throws {
        let routeID = try #require(StravaLive.routeID)
        let detail = try await client.route(routeID)
        let gpx = try await client.routeGPX(routeID)
        print("strava live: route \(detail.segments.count) segments, \(detail.segments.filter { $0.bestElapsedSeconds != nil }.count) with a best; GPX \(gpx.count) bytes")
        #expect(!gpx.isEmpty)
    }

    /// The shape of Strava's real answers: every key path with its JSON type and how many rows carry
    /// it, never a value. It shows where Strava puts a field the decoders miss, such as the best time.
    @Test("Prints the key paths of the activity and route answers", .enabled(if: StravaLive.activityID != nil || StravaLive.routeID != nil))
    func answerShapes() async throws {
        if let activityID = StravaLive.activityID {
            let json = try await Self.rawJSON("activities/\(activityID)?include_all_efforts=true")
            let activity = json as? [String: Any] ?? [:]
            let efforts = activity["segment_efforts"] as? [Any] ?? []
            Self.printShape(of: efforts, label: "effort")
            // Visibility is a word (everyone, followers_only, only_me), not the rider's data, and
            // may be why Strava leaves out ranks and stats.
            print("strava live: activity visibility \(activity["visibility"] ?? "absent"), private \(activity["private"] ?? "absent")")
            let visibilities = efforts.compactMap { ($0 as? [String: Any])?["visibility"] as? String }
            for (value, count) in Dictionary(grouping: visibilities, by: { $0 }).mapValues(\.count) {
                print("strava live: effort visibility \(value) \(count)/\(efforts.count)")
            }
        }
        if let routeID = StravaLive.routeID {
            let json = try await Self.rawJSON("routes/\(routeID)")
            let segments = (json as? [String: Any])?["segments"] as? [Any] ?? []
            Self.printShape(of: segments, label: "route segment")
        }
    }

    static func rawJSON(_ pathAndQuery: String) async throws -> Any {
        var request = URLRequest(url: try #require(URL(string: "https://www.strava.com/api/v3/\(pathAndQuery)")))
        request.setValue("Bearer \(StravaLive.token ?? "")", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        try #require((response as? HTTPURLResponse)?.statusCode == 200)
        return try JSONSerialization.jsonObject(with: data)
    }

    /// "strava live: effort shape 49/49 segment.climb_category: number", one line per path.
    static func printShape(of rows: [Any], label: String) {
        var counts: [String: Int] = [:]
        for row in rows {
            for path in Set(keyPaths(row, prefix: "")) { counts[path, default: 0] += 1 }
        }
        for (path, count) in counts.sorted(by: { $0.key < $1.key }) {
            print("strava live: \(label) shape \(count)/\(rows.count) \(path)")
        }
    }

    static func keyPaths(_ value: Any, prefix: String) -> [String] {
        switch value {
        case let object as [String: Any]:
            return object.flatMap { key, child in keyPaths(child, prefix: prefix.isEmpty ? key : "\(prefix).\(key)") }
        case let array as [Any]:
            return ["\(prefix): array"] + array.flatMap { keyPaths($0, prefix: "\(prefix)[]") }
        case is NSNull:
            return ["\(prefix): null"]
        case let number as NSNumber:
            return ["\(prefix): \(CFGetTypeID(number) == CFBooleanGetTypeID() ? "bool" : "number")"]
        default:
            return ["\(prefix): string"]
        }
    }

    @Test("An activity's segment efforts decode", .enabled(if: StravaLive.activityID != nil))
    func segmentEfforts() async throws {
        let efforts = try await client.segmentEfforts(try #require(StravaLive.activityID))
        print("strava live: \(efforts.count) efforts, \(efforts.filter { $0.prRank != nil }.count) PRs, \(efforts.filter { $0.bestElapsedSeconds != nil }.count) with a best")
    }
}

/// What the live check was given. Outside the suite, which its own traits can't refer to.
private enum StravaLive {
    static let environment = ProcessInfo.processInfo.environment
    static var token: String? { environment["STRAVA_LIVE_TOKEN"] }
    static var activityID: String? { environment["STRAVA_LIVE_ACTIVITY_ID"] }
    static var routeID: String? { environment["STRAVA_LIVE_ROUTE_ID"] }
}
