import Foundation

/// How a `WeatherCondition` is shown (#149): its SF Symbol and its name.
extension WeatherCondition {
    /// The SF Symbol for this sky. Clear and partly cloudy skies have a night form, so an evening
    /// ride doesn't show a sun.
    func symbolName(isDaylight: Bool) -> String {
        switch self {
        case .clear: isDaylight ? "sun.max.fill" : "moon.stars.fill"
        case .partlyCloudy: isDaylight ? "cloud.sun.fill" : "cloud.moon.fill"
        case .cloudy: "cloud.fill"
        case .foggy: "cloud.fog.fill"
        case .drizzle: "cloud.drizzle.fill"
        case .rain: "cloud.rain.fill"
        case .heavyRain: "cloud.heavyrain.fill"
        case .snow: "cloud.snow.fill"
        case .thunderstorm: "cloud.bolt.rain.fill"
        }
    }

    /// Title case, as the row shows it.
    var displayName: String {
        switch self {
        case .clear: "Clear"
        case .partlyCloudy: "Partly Cloudy"
        case .cloudy: "Cloudy"
        case .foggy: "Fog"
        case .drizzle: "Drizzle"
        case .rain: "Rain"
        case .heavyRain: "Heavy Rain"
        case .snow: "Snow"
        case .thunderstorm: "Thunderstorms"
        }
    }

    /// For a reading whose condition is unknown (a case a later SDK adds).
    static let unknownSymbolName = "questionmark.circle"
}
