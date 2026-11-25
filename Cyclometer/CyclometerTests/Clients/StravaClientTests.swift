import ComposableArchitecture
import Foundation
import Testing
@testable import Cyclometer

/// `StravaClient`'s live value (#627, PRD §8.12) against a scripted Strava answering with the JSON
/// fixtures in `Fixtures/`. Their values are made up (the repo is public, so no recorded answer is
/// committed), and their keys follow Strava's real answers as `StravaLiveTests.answerShapes` printed
/// them, not the reference's samples, which show segment stats the real answers don't carry.
@Suite("StravaClient")
struct StravaClientTests {
    /// 2027-01-15 08:00:00 UTC, on a quarter hour.
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let athleteID = "134815"

    // MARK: - Fixtures

    /// Strava: scripted answers per "METHOD /path", each a queue whose last answer repeats, and
    /// every request it received.
    final class Server: Sendable {
        struct Answer {
            var status: Int
            var body: Data
            var headers: [String: String] = [:]
        }

        let requests = LockIsolated<[URLRequest]>([])
        let answers: LockIsolated<[String: [Answer]]>

        init(_ answers: [String: [Answer]] = [:]) {
            self.answers = LockIsolated(answers)
        }

        var transport: StravaTransport {
            StravaTransport { [self] request in
                let url = try #require(request.url)
                requests.withValue { $0.append(request) }
                let key = "\(request.httpMethod ?? "GET") \(url.path())"
                let answer = answers.withValue { answers -> Answer in
                    guard var queue = answers[key], !queue.isEmpty else { return Answer(status: 404, body: Data()) }
                    let next = queue.count > 1 ? queue.removeFirst() : queue[0]
                    answers[key] = queue
                    return next
                }
                return (answer.body, HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: nil, headerFields: answer.headers)!)
            }
        }

        var authorizations: [String?] {
            requests.value.map { $0.value(forHTTPHeaderField: "Authorization") }
        }
    }

    /// `StravaAuthClient`: hands out `a1`, and `a2` once refreshed.
    final class Auth: Sendable {
        let token = LockIsolated("a1")
        /// The token each forced refresh was asked to replace.
        let rejected = LockIsolated<[String]>([])
        let failure: StravaAuthError?

        init(failure: StravaAuthError? = nil) {
            self.failure = failure
        }

        var client: StravaAuthClient {
            StravaAuthClient(
                connect: { throw StravaAuthError.cancelled },
                accessToken: { [self] in
                    if let failure { throw failure }
                    return token.value
                },
                refreshAccessToken: { [self] old in
                    rejected.withValue { $0.append(old) }
                    token.setValue("a2")
                    return "a2"
                },
                disconnect: {},
                handleRedirect: { _ in false }
            )
        }
    }

    static func makeClient(_ server: Server, auth: Auth = Auth(), athleteID: String? = athleteID) -> StravaClient {
        StravaAPI(transport: server.transport, auth: auth.client, athleteID: { athleteID }, now: { now }).client
    }

    static func fixture(_ name: String, _ ext: String = "json") throws -> Data {
        let url = try #require(
            Bundle(for: BundleToken.self).url(forResource: name, withExtension: ext),
            "\(name).\(ext) is not in the test bundle"
        )
        return try Data(contentsOf: url)
    }
    private final class BundleToken {}

    static func ok(_ name: String, _ ext: String = "json") throws -> [Server.Answer] {
        [Server.Answer(status: 200, body: try fixture(name, ext))]
    }

    static func date(_ string: String) throws -> Date {
        try Date(string, strategy: .iso8601)
    }

    // MARK: - Uploads

    @Test("An upload's status decodes from each of Strava's answers", arguments: [
        ("strava-upload-processing", StravaUploadStatus.processing),
        ("strava-upload-ready", .ready(activityID: "9000000001")),
        ("strava-upload-duplicate", .duplicate(activityID: "8800000001")),
        ("strava-upload-error", .failed(reason: "Time information is missing from file.")),
    ])
    func uploadStatusDecodes(fixture: String, expected: StravaUploadStatus) async throws {
        let server = Server(["GET /api/v3/uploads/2000000001": try Self.ok(fixture)])

        let status = try await Self.makeClient(server).uploadStatus(StravaUploadID(rawValue: "2000000001"))

        #expect(status == expected)
        #expect(server.authorizations == ["Bearer a1"])
    }

    @Test("An upload posts the gzipped GPX with the ride's name, description and id")
    func uploadPostsMultipart() async throws {
        let server = Server(["POST /api/v3/uploads": [Server.Answer(status: 201, body: try Self.fixture("strava-upload-processing"))]])
        let gpx = try Self.fixture("strava-route", "gpx")

        let id = try await Self.makeClient(server).upload(StravaUpload(
            gpx: gpx, name: "Morning Ride", description: "Hills", externalID: "6F9619FF-8B86-D011-B42D-00C04FC964FF"
        ))

        #expect(id == StravaUploadID(rawValue: "2000000001"))
        let request = try #require(server.requests.value.first)
        let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
        #expect(contentType.hasPrefix("multipart/form-data; boundary="))
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer a1")
        let body = try #require(request.httpBody)
        for (name, value) in [
            ("data_type", "gpx.gz"), ("sport_type", "Ride"), ("name", "Morning Ride"), ("description", "Hills"),
            ("external_id", "6F9619FF-8B86-D011-B42D-00C04FC964FF"),
        ] {
            #expect(body.range(of: Data("name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8)) != nil, "missing \(name)")
        }
        #expect(body.range(of: Data("name=\"file\"; filename=\"6F9619FF-8B86-D011-B42D-00C04FC964FF.gpx.gz\"".utf8)) != nil)
        #expect(body.range(of: try gpx.gzipped()) != nil)
    }

    @Test("A file Strava rejects at once still returns its id, so polling reports why")
    func rejectedUploadReturnsID() async throws {
        let server = Server(["POST /api/v3/uploads": [Server.Answer(status: 400, body: try Self.fixture("strava-upload-error"))]])

        let id = try await Self.makeClient(server).upload(StravaUpload(gpx: Data("<gpx/>".utf8), name: "Ride", externalID: "x"))

        #expect(id == StravaUploadID(rawValue: "2000000001"))
    }

    @Test("An upload answered without an upload fails with its status")
    func uploadWithoutIDFails() async throws {
        let server = Server(["POST /api/v3/uploads": [Server.Answer(status: 500, body: Data())]])

        await #expect(throws: StravaError.http(status: 500)) {
            try await Self.makeClient(server).upload(StravaUpload(gpx: Data("<gpx/>".utf8), name: "Ride", externalID: "x"))
        }
    }

    // MARK: - Segment efforts

    static let tunnelRoad = StravaSegmentEffort(
        effortID: "2801117330", segmentID: "365235", name: "Tunnel Road",
        distanceMeters: 1826.4, averageGradePercent: 4.1, elapsedSeconds: 412, startIndex: 1110, climbCategory: 0,
        startLatitude: 37.8581, startLongitude: -122.2402, endLatitude: 37.8655, endLongitude: -122.2265,
        prRank: 3, komRank: nil
    )

    static let grizzlyPeak = StravaSegmentEffort(
        effortID: "2801117331", segmentID: "673683", name: "Grizzly Peak Climb",
        distanceMeters: 3412.8, averageGradePercent: 6.4, elapsedSeconds: 1052, startIndex: 2280, climbCategory: 2,
        startLatitude: 37.8702, startLongitude: -122.2541, endLatitude: 37.8811, endLongitude: -122.2433,
        prRank: 1, komRank: 7
    )

    /// Strava's answer has no best time (`StravaLiveTests.answerShapes`), so none is decoded.
    @Test("Segment efforts decode in ride order with PR and KOM ranks, and a segment without a location is dropped")
    func segmentEffortsDecode() async throws {
        let server = Server(["GET /api/v3/activities/9000000001": try Self.ok("strava-activity-efforts")])

        let efforts = try await Self.makeClient(server).segmentEfforts("9000000001")

        #expect(efforts == [Self.tunnelRoad, Self.grizzlyPeak])

        let url = try #require(server.requests.value.first?.url)
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems == [
            URLQueryItem(name: "include_all_efforts", value: "true"),
        ])
    }

    @Test("An activity with no efforts decodes as none")
    func noSegmentEfforts() async throws {
        let server = Server(["GET /api/v3/activities/9000000001": try Self.ok("strava-activity-no-efforts")])

        #expect(try await Self.makeClient(server).segmentEfforts("9000000001") == [])
    }

    // MARK: - Routes

    @Test("A page of routes decodes, with Strava's types passed through")
    func routesDecode() async throws {
        let server = Server(["GET /api/v3/athletes/134815/routes": try Self.ok("strava-routes-page")])

        let routes = try await Self.makeClient(server).routes(2)

        #expect(routes == [
            StravaRouteSummary(
                routeID: "3344024577052366532", name: "Berkeley Hills Loop", distanceMeters: 48211.6,
                elevationGainMeters: 812.3, type: 1, subType: 1, isPrivate: false, isStarred: true,
                updatedAt: try Self.date("2026-10-11T09:15:00Z")
            ),
            StravaRouteSummary(
                routeID: "3344024577052366533", name: "Lake Run", distanceMeters: 10022.0,
                elevationGainMeters: 120.0, type: 2, subType: 4, isPrivate: true, isStarred: false,
                updatedAt: try Self.date("2026-04-02T17:44:10Z")
            ),
        ])
        let url = try #require(server.requests.value.first?.url)
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems == [
            URLQueryItem(name: "page", value: "2"), URLQueryItem(name: "per_page", value: "30"),
        ])
    }

    @Test("Without a connected athlete, routes aren't requested")
    func routesNeedAnAthlete() async throws {
        let server = Server()

        await #expect(throws: StravaAuthError.notConnected) { try await Self.makeClient(server, athleteID: nil).routes(1) }
        #expect(server.requests.value.isEmpty)
    }

    @Test("A route's segments decode, without a best time, which Strava's answer doesn't carry")
    func routeDetailDecodes() async throws {
        let server = Server(["GET /api/v3/routes/3344024577052366532": try Self.ok("strava-route-detail")])

        let detail = try await Self.makeClient(server).route("3344024577052366532")

        #expect(detail.summary.routeID == "3344024577052366532")
        #expect(detail.segments == [
            StravaRouteSegment(
                segmentID: "673683", name: "Grizzly Peak Climb", distanceMeters: 3412.8, averageGradePercent: 6.4,
                climbCategory: 2
            ),
            StravaRouteSegment(
                segmentID: "365235", name: "Tunnel Road", distanceMeters: 1826.4, averageGradePercent: 4.1,
                climbCategory: 0
            ),
        ])
    }

    @Test("A route's GPX is returned as Strava sent it")
    func routeGPX() async throws {
        let gpx = try Self.fixture("strava-route", "gpx")
        let server = Server(["GET /api/v3/routes/3344024577052366532/export_gpx": [Server.Answer(status: 200, body: gpx)]])

        #expect(try await Self.makeClient(server).routeGPX("3344024577052366532") == gpx)
    }

    // MARK: - Gear

    @Test("The athlete's bikes decode, and shoes are left out")
    func bikesDecode() async throws {
        let server = Server(["GET /api/v3/athlete": try Self.ok("strava-athlete")])

        #expect(try await Self.makeClient(server).bikes() == [
            StravaGear(gearID: "b12345678", name: "Road Bike", isPrimary: true, distanceMeters: 18234567.8),
            StravaGear(gearID: "b12345679", name: "Gravel Bike", isPrimary: false, distanceMeters: 2510000.0),
        ])
    }

    @Test("Setting gear puts the gear id on the activity")
    func setGear() async throws {
        let server = Server(["PUT /api/v3/activities/9000000001": [Server.Answer(status: 200, body: Data("{}".utf8))]])

        try await Self.makeClient(server).setGear("9000000001", "b12345678")

        let request = try #require(server.requests.value.first)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(try JSONDecoder().decode([String: String].self, from: try #require(request.httpBody)) == ["gear_id": "b12345678"])
    }

    // MARK: - 401

    @Test("A 401 refreshes the token once and retries with the new one")
    func unauthorizedRetriesOnce() async throws {
        let auth = Auth()
        let server = Server(["GET /api/v3/athlete": [
            Server.Answer(status: 401, body: Data(#"{"message":"Authorization Error"}"#.utf8)),
            Server.Answer(status: 200, body: try Self.fixture("strava-athlete")),
        ]])

        let bikes = try await Self.makeClient(server, auth: auth).bikes()

        #expect(bikes.count == 2)
        #expect(auth.rejected.value == ["a1"])
        #expect(server.authorizations == ["Bearer a1", "Bearer a2"])
    }

    @Test("A 401 after the refresh fails as unauthorized, without refreshing again")
    func unauthorizedTwiceFails() async throws {
        let auth = Auth()
        let server = Server(["GET /api/v3/athlete": [Server.Answer(status: 401, body: Data())]])

        await #expect(throws: StravaError.unauthorized) { try await Self.makeClient(server, auth: auth).bikes() }
        #expect(auth.rejected.value == ["a1"])
        #expect(server.requests.value.count == 2)
    }

    @Test("An account that can't sign a request fails before calling Strava")
    func disconnectedPassesThrough() async throws {
        let server = Server()

        await #expect(throws: StravaAuthError.disconnected) {
            try await Self.makeClient(server, auth: Auth(failure: .disconnected)).bikes()
        }
        #expect(server.requests.value.isEmpty)
    }

    // MARK: - 429 and other failures

    static func limited(overallUsage: String, readUsage: String) -> [Server.Answer] {
        [Server.Answer(status: 429, body: Data(#"{"message":"Rate Limit Exceeded"}"#.utf8), headers: [
            "X-RateLimit-Limit": "200,2000", "X-RateLimit-Usage": overallUsage,
            "X-ReadRateLimit-Limit": "100,1000", "X-ReadRateLimit-Usage": readUsage,
        ])]
    }

    @Test("A 429 with the 15-minute limit spent waits for the next quarter hour")
    func rateLimitedUntilQuarterHour() async throws {
        let server = Server(["GET /api/v3/athlete": Self.limited(overallUsage: "201,900", readUsage: "101,850")])

        await #expect(throws: StravaError.rateLimited(until: Self.now.addingTimeInterval(15 * 60))) {
            try await Self.makeClient(server).bikes()
        }
    }

    @Test("A 429 with a daily limit spent waits for midnight UTC")
    func rateLimitedUntilMidnight() async throws {
        let server = Server(["GET /api/v3/athlete": Self.limited(overallUsage: "60,1100", readUsage: "50,1000")])

        await #expect(throws: StravaError.rateLimited(until: try Self.date("2027-01-16T00:00:00Z"))) {
            try await Self.makeClient(server).bikes()
        }
    }

    @Test("A 429 without rate-limit headers waits for the next quarter hour")
    func rateLimitedWithoutHeaders() async throws {
        let server = Server(["GET /api/v3/athlete": [Server.Answer(status: 429, body: Data())]])

        await #expect(throws: StravaError.rateLimited(until: Self.now.addingTimeInterval(15 * 60))) {
            try await Self.makeClient(server).bikes()
        }
    }

    @Test("A server error fails with its status")
    func serverErrorFails() async throws {
        let server = Server(["GET /api/v3/athlete": [Server.Answer(status: 503, body: Data())]])

        await #expect(throws: StravaError.http(status: 503)) { try await Self.makeClient(server).bikes() }
    }

    @Test("A 200 that doesn't decode is an invalid response")
    func undecodableAnswerFails() async throws {
        let server = Server(["GET /api/v3/athlete": [Server.Answer(status: 200, body: Data("<html/>".utf8))]])

        await #expect(throws: StravaError.invalidResponse) { try await Self.makeClient(server).bikes() }
    }

    // MARK: - Mock

    @Test("The mock walks an upload through its scripted statuses, the last repeating")
    func mockWalksUploadStatuses() async throws {
        let client = StravaClient.mock(uploadStatuses: [.processing, .ready(activityID: "9")])
        let id = try await client.upload(StravaUpload(gpx: Data(), name: "Ride", externalID: "x"))

        #expect(try await client.uploadStatus(id) == .processing)
        #expect(try await client.uploadStatus(id) == .ready(activityID: "9"))
        #expect(try await client.uploadStatus(id) == .ready(activityID: "9"))
    }
}
