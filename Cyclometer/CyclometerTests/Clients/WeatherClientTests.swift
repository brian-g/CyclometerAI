import Foundation
import Testing
import WeatherKit
@testable import Cyclometer

@Suite("WeatherClient")
struct WeatherClientTests {

    private static let coordinate = RouteCoordinate(latitude: 46.8772, longitude: -96.7898)

    // MARK: - Condition mapping

    /// Every WeatherKit condition, pinned to the app condition it folds into. Keyed by WeatherKit's
    /// raw value so a case a later SDK adds has no entry and fails `everyConditionIsPinned`.
    private static let expected: [String: Cyclometer.WeatherCondition?] = [
        WeatherKit.WeatherCondition.clear.rawValue: .clear,
        WeatherKit.WeatherCondition.mostlyClear.rawValue: .clear,
        WeatherKit.WeatherCondition.partlyCloudy.rawValue: .partlyCloudy,
        WeatherKit.WeatherCondition.cloudy.rawValue: .cloudy,
        WeatherKit.WeatherCondition.mostlyCloudy.rawValue: .cloudy,
        WeatherKit.WeatherCondition.foggy.rawValue: .foggy,
        WeatherKit.WeatherCondition.haze.rawValue: .foggy,
        WeatherKit.WeatherCondition.smoky.rawValue: .foggy,
        WeatherKit.WeatherCondition.blowingDust.rawValue: .foggy,
        WeatherKit.WeatherCondition.drizzle.rawValue: .drizzle,
        WeatherKit.WeatherCondition.freezingDrizzle.rawValue: .drizzle,
        WeatherKit.WeatherCondition.rain.rawValue: .rain,
        WeatherKit.WeatherCondition.freezingRain.rawValue: .rain,
        WeatherKit.WeatherCondition.sunShowers.rawValue: .rain,
        WeatherKit.WeatherCondition.heavyRain.rawValue: .heavyRain,
        WeatherKit.WeatherCondition.snow.rawValue: .snow,
        WeatherKit.WeatherCondition.heavySnow.rawValue: .snow,
        WeatherKit.WeatherCondition.flurries.rawValue: .snow,
        WeatherKit.WeatherCondition.sunFlurries.rawValue: .snow,
        WeatherKit.WeatherCondition.blowingSnow.rawValue: .snow,
        WeatherKit.WeatherCondition.blizzard.rawValue: .snow,
        WeatherKit.WeatherCondition.sleet.rawValue: .snow,
        WeatherKit.WeatherCondition.wintryMix.rawValue: .snow,
        WeatherKit.WeatherCondition.thunderstorms.rawValue: .thunderstorm,
        WeatherKit.WeatherCondition.isolatedThunderstorms.rawValue: .thunderstorm,
        WeatherKit.WeatherCondition.scatteredThunderstorms.rawValue: .thunderstorm,
        WeatherKit.WeatherCondition.strongStorms.rawValue: .thunderstorm,
        WeatherKit.WeatherCondition.tropicalStorm.rawValue: .thunderstorm,
        WeatherKit.WeatherCondition.hurricane.rawValue: .thunderstorm,
        WeatherKit.WeatherCondition.hail.rawValue: .thunderstorm,
        WeatherKit.WeatherCondition.hot.rawValue: nil,
        WeatherKit.WeatherCondition.frigid.rawValue: nil,
        WeatherKit.WeatherCondition.windy.rawValue: nil,
        WeatherKit.WeatherCondition.breezy.rawValue: nil,
    ]

    @Test("Each WeatherKit condition maps to its pinned app condition",
          arguments: WeatherKit.WeatherCondition.allCases)
    func conditionMapping(_ condition: WeatherKit.WeatherCondition) throws {
        let pinned = try #require(Self.expected[condition.rawValue], "\(condition) has no pinned mapping")
        #expect(Cyclometer.WeatherCondition(condition) == pinned)
    }

    @Test("Every WeatherKit condition is pinned, and nothing else is")
    func everyConditionIsPinned() {
        #expect(Set(WeatherKit.WeatherCondition.allCases.map(\.rawValue)) == Set(Self.expected.keys))
    }

    // MARK: - testValue fixtures

    @Test("testValue reports the fixture's current conditions, with no precipitation chance")
    func testValueCurrent() async throws {
        let reading = try await WeatherClient.testValue.current(Self.coordinate)
        #expect(reading == .fixture)
        #expect(reading.precipitationChance == nil)
    }

    @Test("testValue's forecast is hourly, ascending, and in range")
    func testValueForecast() async throws {
        let hours = try await WeatherClient.testValue.hourlyForecast(Self.coordinate)
        #expect(hours == WeatherReading.fixtureHourly)
        #expect(!hours.isEmpty)
        for (earlier, later) in zip(hours, hours.dropFirst()) {
            #expect(later.date.timeIntervalSince(earlier.date) == 3600)
        }
        for hour in hours {
            let chance = try #require(hour.precipitationChance)
            #expect((0...1).contains(chance))
            #expect((0...1).contains(hour.humidity))
        }
        // The rain chance climbs, so a consumer's threshold has something to cross.
        #expect(hours.first?.precipitationChance ?? 1 < hours.last?.precipitationChance ?? 0)
    }

    @Test("testValue reports the fixture attribution")
    func testValueAttribution() async throws {
        #expect(try await WeatherClient.testValue.attribution() == .fixture)
    }

    // MARK: - unavailable

    @Test("unavailable throws from every call")
    func unavailableThrows() async {
        let client = WeatherClient.unavailable
        await #expect(throws: WeatherClientError.unavailable) { try await client.current(Self.coordinate) }
        await #expect(throws: WeatherClientError.unavailable) { try await client.hourlyForecast(Self.coordinate) }
        await #expect(throws: WeatherClientError.unavailable) { try await client.attribution() }
    }
}
