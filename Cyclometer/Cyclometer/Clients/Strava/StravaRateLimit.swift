import Foundation

/// Strava's rate-limit headers on one answer (PRD §8.12). The limits belong to the app and every
/// rider shares them: by default 200 requests per 15 minutes and 2,000 a day overall, of which
/// non-upload requests get 100 and 1,000.
///
/// Each header is "15-minute, daily", e.g. `X-RateLimit-Usage: 314,1536`. The 15-minute window
/// resets on the quarter hour and the daily one at midnight UTC (developers.strava.com/docs/rate-limits).
struct StravaRateLimit: Equatable, Sendable {
    struct Window: Equatable, Sendable {
        var usage: Int
        var limit: Int
        var isSpent: Bool { usage >= limit }
    }

    struct Windows: Equatable, Sendable {
        var fifteenMinutes: Window
        var daily: Window
    }

    /// Every request.
    var overall: Windows?
    /// Every request except uploads (upload polling included).
    var read: Windows?

    init(overall: Windows?, read: Windows?) {
        self.overall = overall
        self.read = read
    }

    /// Read from an answer's headers. Header names are matched without case: Strava's own docs
    /// write both `X-RateLimit` and `X-Ratelimit`. Nil when neither pair is there.
    init?(_ response: HTTPURLResponse) {
        func windows(_ prefix: String) -> Windows? {
            guard let limits = Self.pair(response.value(forHTTPHeaderField: "\(prefix)-Limit")),
                  let usages = Self.pair(response.value(forHTTPHeaderField: "\(prefix)-Usage")) else { return nil }
            return Windows(
                fifteenMinutes: Window(usage: usages.0, limit: limits.0),
                daily: Window(usage: usages.1, limit: limits.1)
            )
        }
        overall = windows("X-RateLimit")
        read = windows("X-ReadRateLimit")
        if overall == nil && read == nil { return nil }
    }

    /// Whether a daily count that applies to the request has reached its limit, so it can't
    /// succeed before midnight UTC. An upload counts only against `overall`, so a spent `read`
    /// count doesn't hold it.
    func isDailySpent(isUpload: Bool = false) -> Bool {
        overall?.daily.isSpent == true || (!isUpload && read?.daily.isSpent == true)
    }

    /// When a refused request may be tried again: midnight UTC when a daily count that applies to
    /// it is spent, otherwise the next quarter hour. Strictly after `now`, since the window `now`
    /// falls in is the one that refused.
    func resetDate(after now: Date, isUpload: Bool = false) -> Date {
        isDailySpent(isUpload: isUpload) ? Self.nextMidnightUTC(after: now) : Self.nextQuarterHour(after: now)
    }

    /// :00, :15, :30 or :45, whichever comes next after `now`.
    static func nextQuarterHour(after now: Date) -> Date {
        let quarter: TimeInterval = 15 * 60
        return Date(timeIntervalSince1970: (now.timeIntervalSince1970 / quarter).rounded(.down) * quarter + quarter)
    }

    /// The next 00:00 UTC after `now`.
    static func nextMidnightUTC(after now: Date) -> Date {
        let day: TimeInterval = 24 * 60 * 60
        return Date(timeIntervalSince1970: (now.timeIntervalSince1970 / day).rounded(.down) * day + day)
    }

    /// "200,2000" → (200, 2000).
    private static func pair(_ header: String?) -> (Int, Int)? {
        guard let parts = header?.split(separator: ",").map({ Int($0.trimmingCharacters(in: .whitespaces)) }),
              parts.count == 2, let first = parts[0], let second = parts[1] else { return nil }
        return (first, second)
    }
}
