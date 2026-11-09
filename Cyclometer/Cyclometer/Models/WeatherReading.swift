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
    /// `nil` only for a condition a later SDK adds (see `WeatherCondition.init`).
    var condition: WeatherCondition?
    /// Chance of precipitation, 0…1. Forecast hours only: WeatherKit doesn't give one for
    /// current conditions, so there it is `nil`.
    var precipitationChance: Double?
    /// Whether the sun is up then, so a clear night shows a moon rather than a sun.
    var isDaylight: Bool
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
    /// unchanged by this. The conditions that describe temperature or wind (both of which a
    /// reading already carries) say nothing about the sky, so for those the sky comes from
    /// `cloudCover` (0…1) instead. `nil` only for a case a later SDK adds.
    init?(_ condition: WeatherKit.WeatherCondition, cloudCover: Double) {
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
            self.init(cloudCover: cloudCover)
        @unknown default:
            return nil
        }
    }

    /// The sky from cloud cover alone, in the oktas (eighths of sky) the National Weather Service
    /// uses: up to 2/8 is clear or mostly clear, 3–5/8 partly cloudy, 6/8 and over mostly cloudy
    /// or cloudy. Those groups fold the same way as WeatherKit's sky conditions above.
    init(cloudCover: Double) {
        switch cloudCover * Self.oktasPerSky {
        case ..<Self.clearOktasBelow: self = .clear
        case ..<Self.partlyCloudyOktasBelow: self = .partlyCloudy
        default: self = .cloudy
        }
    }

    private static let oktasPerSky = 8.0
    /// Halfway between the bands, since cloud cover is continuous.
    private static let clearOktasBelow = 2.5
    private static let partlyCloudyOktasBelow = 5.5
}

// MARK: - Fixtures

extension WeatherReading {
    /// One fixed instant, so anything rendered from the fixtures is the same on every run. On the
    /// hour (2026-09-21 14:00 UTC), as WeatherKit's forecast hours are.
    static let fixtureDate = Date(timeIntervalSince1970: 1_789_999_200)

    /// `WeatherClient.testValue`'s current conditions: a mild, breezy, partly cloudy day.
    static let fixture = WeatherReading(
        date: fixtureDate,
        temperature: Measurement(value: 18, unit: .celsius),
        windSpeed: Measurement(value: 14, unit: .kilometersPerHour),
        windDirection: Measurement(value: 270, unit: .degrees),
        humidity: 0.62,
        condition: .partlyCloudy,
        precipitationChance: nil,
        isDaylight: true
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
            precipitationChance: 0.1 + 0.6 * progress,
            isDaylight: true
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
