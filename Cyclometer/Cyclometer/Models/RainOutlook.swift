import Foundation

/// Rain the rider is about to meet (#150): the first hour of a forecast, among the one under way
/// and those starting within `window`, whose chance of precipitation is at least `threshold`.
/// While there is one, W10 shows it in place of the wind.
struct RainOutlook: Equatable, Sendable {
    /// How far ahead W10 looks: far enough to turn for home, near enough to be about this ride.
    static let window: TimeInterval = 2 * 3600
    /// The chance of precipitation at which an hour counts as rain: more likely than not.
    static let threshold = 0.5

    /// Chance of precipitation in that hour, 0…1.
    var chance: Double
    /// The start of that hour.
    var start: Date
    /// That hour had already begun when the forecast was fetched: the rain is "now".
    var isUnderWay: Bool
    /// The hour's sky, for its symbol. Nil for a condition a later SDK adds.
    var condition: WeatherCondition?
    var isDaylight: Bool

    /// Nil when no hour in the window reaches the threshold.
    init?(_ forecast: AttributedForecast) {
        let wet = forecast.hours(within: Self.window).first { ($0.precipitationChance ?? 0) >= Self.threshold }
        guard let wet, let chance = wet.precipitationChance else { return nil }
        self.chance = chance
        start = wet.date
        isUnderWay = wet.date <= forecast.fetchedAt
        condition = wet.condition
        isDaylight = wet.isDaylight
    }

    /// The hour's own symbol when its sky is precipitation; rain otherwise, since an hour can be
    /// "Cloudy" overall and still more likely wet than not.
    var symbolName: String {
        precipitation?.symbolName(isDaylight: isDaylight) ?? Self.rainSymbolName
    }

    /// "Snow", "Thunderstorms"; "Rain" for an hour whose sky isn't precipitation.
    var name: String {
        precipitation?.displayName ?? "Rain"
    }

    /// The hour's sky when it is precipitation, which the card names and draws; nil for any other.
    private var precipitation: WeatherCondition? {
        switch condition {
        case .drizzle, .rain, .heavyRain, .snow, .thunderstorm: condition
        case .clear, .partlyCloudy, .cloudy, .foggy, nil: nil
        }
    }

    private static let rainSymbolName = "cloud.rain.fill"
}
