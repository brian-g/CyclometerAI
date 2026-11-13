import Foundation
import Testing
@testable import Cyclometer

/// #204 — which forecast column reads "Now", and which sky a past ride's row names.
@Suite("Weather display")
struct WeatherDisplayTests {

    private static let hours = WeatherReading.fixtureHourly
    private static let hour = AttributedForecast.hourLength

    // MARK: HourlyForecastStrip.isNow

    @Test("Now is the hour that contains the clock, from its first second to before the next")
    func nowIsTheHourUnderWay() {
        let first = Self.hours[0]
        #expect(HourlyForecastStrip.isNow(first, at: first.date))
        #expect(HourlyForecastStrip.isNow(first, at: WeatherReading.fixtureNow))
        #expect(!HourlyForecastStrip.isNow(first, at: first.date.addingTimeInterval(Self.hour)))
        #expect(!HourlyForecastStrip.isNow(first, at: first.date.addingTimeInterval(-1)))
    }

    /// The #149 review's case: a strip that starts later, or stays up past the hour.
    @Test("A strip that starts later has no Now; one left up past the hour moves Now along")
    func nowIsNotTheFirstColumn() {
        let later = Array(Self.hours.dropFirst(2).prefix(4))
        #expect(!later.contains { HourlyForecastStrip.isNow($0, at: WeatherReading.fixtureNow) })

        let strip = Array(Self.hours.prefix(4))
        let twoHoursOn = WeatherReading.fixtureNow.addingTimeInterval(2 * Self.hour)
        #expect(strip.map { HourlyForecastStrip.isNow($0, at: twoHoursOn) } == [false, false, true, false])
    }

    // MARK: RideWeatherSummary.prevailingCondition

    private static func sample(_ minutes: Double, _ condition: WeatherCondition?) -> RideWeatherSample {
        RideWeatherSample(date: WeatherReading.fixtureDate.addingTimeInterval(minutes * 60), temperatureCelsius: 15,
                          humidity: 0.5, windSpeedMPS: 3, windFromDegrees: 270, condition: condition)
    }

    @Test("The prevailing sky is the one recorded most often")
    func prevailingIsTheMostFrequent() {
        let summary = RideWeatherSummary(samples: [
            Self.sample(0, .partlyCloudy), Self.sample(10, .rain), Self.sample(20, .rain), Self.sample(30, .cloudy),
        ])
        #expect(summary.prevailingCondition == .rain)
    }

    @Test("On a tie, the earliest of the tied skies, whatever order the samples are in")
    func prevailingTieGoesToTheEarliest() {
        let summary = RideWeatherSummary(samples: [
            Self.sample(30, .cloudy), Self.sample(20, .clear), Self.sample(0, .clear), Self.sample(10, .cloudy),
        ])
        #expect(summary.prevailingCondition == .clear)
    }

    @Test("No samples, or none with a known sky, has no prevailing sky")
    func prevailingNeedsAKnownSky() {
        #expect(RideWeatherSummary(samples: []).prevailingCondition == nil)
        #expect(RideWeatherSummary(samples: [Self.sample(0, nil), Self.sample(10, nil)]).prevailingCondition == nil)
        #expect(RideWeatherSummary(samples: [Self.sample(0, nil), Self.sample(10, .snow)]).prevailingCondition == .snow)
    }
}
