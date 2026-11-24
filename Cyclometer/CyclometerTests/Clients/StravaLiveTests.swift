import Foundation
import Testing
@testable import Cyclometer

/// `StravaClient`'s decoders against Strava itself (#627). The fixtures are built from Strava's
/// reference, so this is what proves they match real answers. Off unless a token is passed, so it
/// never runs in CI. It only reads, and writes and stores nothing.
///
/// Prefix each variable with `TEST_RUNNER_` on the `xcodebuild test` command line:
/// - `STRAVA_LIVE_TOKEN`: an access token with `read,read_all,profile:read_all,activity:read_all`
/// - `STRAVA_LIVE_ATHLETE_ID`: the token's athlete, for routes
/// - `STRAVA_LIVE_ACTIVITY_ID`, `STRAVA_LIVE_ROUTE_ID`: optional; their tests are skipped without them
@Suite("Strava live", .enabled(if: StravaLive.token != nil, "Set STRAVA_LIVE_TOKEN to check the decoders against Strava"))
struct StravaLiveTests {
    let client: StravaClient = {
        let token = StravaLive.token ?? ""
        let auth = StravaAuthClient(
            connect: { throw StravaAuthError.cancelled },
            accessToken: { token },
            // No refresh token here: the retry after a 401 resends the same token, so a token Strava
            // refuses fails as `StravaError.unauthorized`.
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
