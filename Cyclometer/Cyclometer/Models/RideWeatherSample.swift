import Foundation

/// The weather at one moment of a ride (#151): the current conditions from one of the forecasts
/// `RideWeatherFeature` fetches for W10, kept so S15 can show the ride's temperature and humidity
/// ranges and how the wind met the rider. Stored on `Ride` as JSON, in plain SI numbers rather than
/// `WeatherReading`'s `Measurement`s, so the stored shape doesn't depend on Foundation's encoding of
/// a unit.
struct RideWeatherSample: Codable, Sendable, Equatable {
    /// WeatherKit's observation time.
    var date: Date
    var temperatureCelsius: Double
    /// Relative humidity, 0…1.
    var humidity: Double
    var windSpeedMPS: Double
    /// Where the wind blows *from*, degrees clockwise from true north (meteorological).
    var windFromDegrees: Double
    var condition: WeatherCondition?
}

extension RideWeatherSample {
    /// Nil when WeatherKit sent a non-finite number: JSON can't encode one, and `Ride.weather`'s
    /// setter would then drop every sample of the ride (lessons, #191).
    init?(_ reading: WeatherReading) {
        let temperature = reading.temperature.converted(to: .celsius).value
        let windSpeed = reading.windSpeed.converted(to: .metersPerSecond).value
        let windFrom = reading.windDirection.converted(to: .degrees).value
        guard temperature.isFinite, reading.humidity.isFinite, windSpeed.isFinite, windFrom.isFinite else {
            return nil
        }
        self.init(
            date: reading.date,
            temperatureCelsius: temperature,
            humidity: reading.humidity,
            windSpeedMPS: windSpeed,
            windFromDegrees: windFrom,
            condition: reading.condition
        )
    }
}

extension RideWeatherSample {
    /// An hour's ride for previews and snapshots: warming from 12 to 18 °C as the humidity falls
    /// from 74 to 52 %, in a westerly picking up from 3 to 5 m/s. One sample every 10 minutes from
    /// `WeatherReading.fixtureDate`, as `RideWeatherFeature` records them.
    static let fixtureRide: [RideWeatherSample] = (0...6).map { step in
        RideWeatherSample(
            date: WeatherReading.fixtureDate.addingTimeInterval(Double(step) * 600),
            temperatureCelsius: 12 + Double(step),
            humidity: 0.74 - 0.037 * Double(step),
            windSpeedMPS: 3 + Double(step) / 3,
            windFromDegrees: 270,
            condition: .partlyCloudy
        )
    }
}

extension [RideWeatherSample] {
    /// Adds the conditions from a new forecast, unless WeatherKit sent the observation already
    /// held: a refetch inside its update interval returns the same one.
    mutating func record(_ reading: WeatherReading) {
        guard let sample = RideWeatherSample(reading), sample.date != last?.date else { return }
        append(sample)
    }
}
