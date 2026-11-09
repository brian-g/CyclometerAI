import Foundation
import WeatherKit

/// The weather at one place and time, as `WeatherClient` reports it (#148): either current
/// conditions or one hour of the forecast. The app's own type, not WeatherKit's, so features and
/// their tests never touch WeatherKit, whose values have no public initialisers.
struct WeatherReading: Equatable, Sendable {
    /// When these conditions hold: WeatherKit's observation time for current conditions, or the
    /// start of the forecast hour.
    var date: Date
    var temperature: Measurement<UnitTemperature>
    var windSpeed: Measurement<UnitSpeed>
    /// Where the wind blows *from*, clockwise from true north (meteorological, like
    /// `RideWeather.windDirectionDegrees`).
    var windDirection: Measurement<UnitAngle>
    /// Relative humidity, 0…1.
    var humidity: Double
    /// `nil` when WeatherKit's condition says nothing about the sky (see `WeatherCondition.init`).
    var condition: WeatherCondition?
    /// Chance of precipitation, 0…1. Forecast hours only: WeatherKit doesn't give one for
    /// current conditions, so there it is `nil`.
    var precipitationChance: Double?
}

/// What WeatherKit's terms ask for wherever its data is shown: the Apple Weather mark and a link
/// to its legal attribution page. Named to stay clear of `WeatherKit.WeatherAttribution`.
struct WeatherSourceAttribution: Equatable, Sendable {
    var serviceName: String
    var legalPageURL: URL
    /// The mark for a light background.
    var combinedMarkLightURL: URL
    /// The mark for a dark background.
    var combinedMarkDarkURL: URL
}

extension WeatherCondition {
    /// Folds WeatherKit's conditions into the app's nine, which are persisted on `Ride` and
    /// unchanged by this. `nil` for the conditions that describe temperature or wind (both of
    /// which a reading already carries) and say nothing about the sky, and for any case a later
    /// SDK adds.
    init?(_ condition: WeatherKit.WeatherCondition) {
        switch condition {
        case .clear, .mostlyClear:
            self = .clear
        case .partlyCloudy:
            self = .partlyCloudy
        case .cloudy, .mostlyCloudy:
            self = .cloudy
        case .foggy, .haze, .smoky, .blowingDust:
            self = .foggy
        case .drizzle, .freezingDrizzle:
            self = .drizzle
        case .rain, .freezingRain, .sunShowers:
            self = .rain
        case .heavyRain:
            self = .heavyRain
        case .snow, .heavySnow, .flurries, .sunFlurries, .blowingSnow, .blizzard, .sleet, .wintryMix:
            self = .snow
        case .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms,
             .tropicalStorm, .hurricane, .hail:
            self = .thunderstorm
        case .hot, .frigid, .windy, .breezy:
            return nil
        @unknown default:
            return nil
        }
    }
}

// MARK: - Fixtures

extension WeatherReading {
    /// One fixed instant, so anything rendered from the fixtures is the same on every run.
    static let fixtureDate = Date(timeIntervalSince1970: 1_790_000_000)

    /// `WeatherClient.testValue`'s current conditions: a mild, breezy, partly cloudy day.
    static let fixture = WeatherReading(
        date: fixtureDate,
        temperature: Measurement(value: 18, unit: .celsius),
        windSpeed: Measurement(value: 14, unit: .kilometersPerHour),
        windDirection: Measurement(value: 270, unit: .degrees),
        humidity: 0.62,
        condition: .partlyCloudy,
        precipitationChance: nil
    )

    /// `WeatherClient.testValue`'s forecast: twelve hours from `fixtureDate`, warming then
    /// cooling, the wind backing south, and the chance of rain rising from 0.1 to 0.7, so a
    /// consumer's rain threshold has something to cross.
    static let fixtureHourly: [WeatherReading] = (0..<12).map { hour in
        let progress = Double(hour) / 11
        return WeatherReading(
            date: fixtureDate.addingTimeInterval(Double(hour) * 3600),
            temperature: Measurement(value: 18 + 4 * sin(progress * .pi), unit: .celsius),
            windSpeed: Measurement(value: 14 + 8 * progress, unit: .kilometersPerHour),
            windDirection: Measurement(value: 270 - 90 * progress, unit: .degrees),
            humidity: 0.62 + 0.3 * progress,
            condition: progress < 0.5 ? .partlyCloudy : progress < 0.8 ? .cloudy : .rain,
            precipitationChance: 0.1 + 0.6 * progress
        )
    }
}

extension WeatherSourceAttribution {
    /// Stand-in URLs: the live marks are served by WeatherKit and change with locale.
    static let fixture = WeatherSourceAttribution(
        serviceName: "Weather",
        legalPageURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!,
        combinedMarkLightURL: URL(string: "https://example.com/weather-mark-light.png")!,
        combinedMarkDarkURL: URL(string: "https://example.com/weather-mark-dark.png")!
    )
}
