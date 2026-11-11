import Foundation

/// One answer from WeatherKit as a screen shows it (#149, #150): current conditions, the hourly
/// forecast, and the attribution its terms require beside them. S05.1's Weather group and W10's
/// sheet both show this.
struct AttributedForecast: Equatable, Sendable {
    var current: WeatherReading
    /// WeatherKit's whole forecast; `hours(within:)` picks the ones a screen shows.
    var hourly: [WeatherReading]
    var attribution: WeatherSourceAttribution
    /// When it was fetched, which is the hourly strip's "Now".
    var fetchedAt: Date

    /// WeatherKit forecasts by the hour; each entry is dated at the start of its hour.
    static let hourLength: TimeInterval = 3600

    /// The hour under way at `start` (by default, when the weather was fetched), then each hour
    /// that starts within `window` of it.
    func hours(within window: TimeInterval, from start: Date? = nil) -> [WeatherReading] {
        let start = start ?? fetchedAt
        let end = start.addingTimeInterval(window)
        return hourly.filter { $0.date.addingTimeInterval(Self.hourLength) > start && $0.date < end }
    }
}

extension AttributedForecast {
    /// `WeatherClient.testValue`'s answer, fetched at `WeatherReading.fixtureNow`.
    static let fixture = AttributedForecast(
        current: .fixture,
        hourly: WeatherReading.fixtureHourly,
        attribution: .fixture,
        fetchedAt: WeatherReading.fixtureNow
    )

    /// `fixture` moved to `now`: fetched then, its hours from the one under way. For a sample
    /// shown against the real clock (S08's), which would read a fixed date as stale.
    static func fixture(at now: Date) -> AttributedForecast {
        let shift = now.timeIntervalSince(fixture.fetchedAt)
        var forecast = fixture
        forecast.fetchedAt = now
        forecast.current.date.addTimeInterval(shift)
        for index in forecast.hourly.indices {
            forecast.hourly[index].date.addTimeInterval(shift)
        }
        return forecast
    }
}
