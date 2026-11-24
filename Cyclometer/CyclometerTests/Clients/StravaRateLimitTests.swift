import Foundation
import Testing
@testable import Cyclometer

/// Strava's rate-limit headers and when a refused request may try again (#627, PRD §8.12).
@Suite("StravaRateLimit")
struct StravaRateLimitTests {
    static func response(_ headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://www.strava.com/api/v3/athlete")!, statusCode: 200, httpVersion: nil, headerFields: headers)!
    }

    static func date(_ string: String) throws -> Date {
        try Date(string, strategy: .iso8601)
    }

    static func windows(_ fifteen: (Int, Int), _ daily: (Int, Int)) -> StravaRateLimit.Windows {
        StravaRateLimit.Windows(
            fifteenMinutes: .init(usage: fifteen.0, limit: fifteen.1),
            daily: .init(usage: daily.0, limit: daily.1)
        )
    }

    // MARK: - Headers

    @Test("Both pairs parse, whatever the header's case")
    func parsesHeaders() throws {
        let limit = try #require(StravaRateLimit(Self.response([
            "X-Ratelimit-Limit": "200,2000", "X-Ratelimit-Usage": "12, 340",
            "X-ReadRateLimit-Limit": "100,1000", "X-ReadRateLimit-Usage": "10,300",
        ])))

        #expect(limit == StravaRateLimit(
            overall: Self.windows((12, 200), (340, 2000)),
            read: Self.windows((10, 100), (300, 1000))
        ))
    }

    @Test("Without the headers there is no rate limit to read")
    func missingHeaders() {
        #expect(StravaRateLimit(Self.response([:])) == nil)
    }

    @Test("A malformed pair is ignored, and the other kept")
    func malformedHeader() throws {
        let limit = try #require(StravaRateLimit(Self.response([
            "X-RateLimit-Limit": "200", "X-RateLimit-Usage": "12,340",
            "X-ReadRateLimit-Limit": "100,1000", "X-ReadRateLimit-Usage": "10,300",
        ])))

        #expect(limit.overall == nil)
        #expect(limit.read == Self.windows((10, 100), (300, 1000)))
    }

    // MARK: - Reset

    @Test("The next quarter hour is strictly after now", arguments: [
        ("2027-01-15T08:00:00Z", "2027-01-15T08:15:00Z"),
        ("2027-01-15T08:14:59Z", "2027-01-15T08:15:00Z"),
        ("2027-01-15T08:15:00Z", "2027-01-15T08:30:00Z"),
        ("2027-01-15T08:59:59Z", "2027-01-15T09:00:00Z"),
        ("2027-01-15T23:50:00Z", "2027-01-16T00:00:00Z"),
    ])
    func nextQuarterHour(now: String, expected: String) throws {
        #expect(StravaRateLimit.nextQuarterHour(after: try Self.date(now)) == (try Self.date(expected)))
    }

    @Test("The next midnight UTC is strictly after now", arguments: [
        ("2027-01-15T08:00:00Z", "2027-01-16T00:00:00Z"),
        ("2027-01-15T00:00:00Z", "2027-01-16T00:00:00Z"),
        ("2027-01-15T23:59:59Z", "2027-01-16T00:00:00Z"),
    ])
    func nextMidnight(now: String, expected: String) throws {
        #expect(StravaRateLimit.nextMidnightUTC(after: try Self.date(now)) == (try Self.date(expected)))
    }

    @Test("A spent daily count, overall or read, waits for midnight; a spent 15-minute count for the quarter hour")
    func resetDate() throws {
        let now = try Self.date("2027-01-15T08:05:00Z")
        let quarter = try Self.date("2027-01-15T08:15:00Z")
        let midnight = try Self.date("2027-01-16T00:00:00Z")

        let fifteenSpent = StravaRateLimit(overall: Self.windows((200, 200), (900, 2000)), read: Self.windows((90, 100), (800, 1000)))
        let overallDailySpent = StravaRateLimit(overall: Self.windows((20, 200), (2000, 2000)), read: Self.windows((10, 100), (800, 1000)))
        let readDailySpent = StravaRateLimit(overall: Self.windows((20, 200), (1500, 2000)), read: Self.windows((10, 100), (1000, 1000)))

        #expect(fifteenSpent.resetDate(after: now) == quarter)
        #expect(overallDailySpent.resetDate(after: now) == midnight)
        #expect(readDailySpent.resetDate(after: now) == midnight)
    }
}
