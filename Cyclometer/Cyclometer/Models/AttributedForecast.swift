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

    /// The hour under way when the weather was fetched, then each hour that starts within
    /// `window` of it.
    func hours(within window: TimeInterval) -> [WeatherReading] {
        let end = fetchedAt.addingTimeInterval(window)
        return hourly.filter { $0.date.addingTimeInterval(Self.hourLength) > fetchedAt && $0.date < end }
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
}
