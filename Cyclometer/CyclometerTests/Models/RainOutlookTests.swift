import Foundation
import Testing
@testable import Cyclometer

/// #150 — when W10 shows rain in place of the wind. The fixture forecast is fetched at 14:40, so
/// its window is the hours starting 14:00, 15:00 and 16:00, none of which reaches 50%.
@Suite("RainOutlook")
struct RainOutlookTests {

    /// When the fixture forecast was fetched, 14:40.
    private static let now = WeatherReading.fixtureNow

    private func forecast(chance: Double, hour: Int, condition: WeatherCondition? = .rain) -> AttributedForecast {
        var forecast = AttributedForecast.fixture
        forecast.hourly[hour].precipitationChance = chance
        forecast.hourly[hour].condition = condition
        return forecast
    }

    @Test("No hour in the window at 50% is no rain")
    func none() {
        #expect(RainOutlook(.fixture, now: Self.now) == nil)
        #expect(RainOutlook(forecast(chance: 0.49, hour: 1), now: Self.now) == nil)
    }

    @Test("An hour at 50% within two hours is rain, from the start of that hour")
    func later() throws {
        let outlook = try #require(RainOutlook(forecast(chance: 0.5, hour: 2), now: Self.now))
        #expect(outlook.chance == 0.5)
        #expect(outlook.start == WeatherReading.fixtureDate.addingTimeInterval(2 * 3600))
        #expect(!outlook.isUnderWay)
    }

    @Test("The hour under way counts, and reads as now")
    func underWay() throws {
        let outlook = try #require(RainOutlook(forecast(chance: 0.8, hour: 0), now: Self.now))
        #expect(outlook.start == WeatherReading.fixtureDate)
        #expect(outlook.isUnderWay)
    }

    /// #150 review: measured from the clock, not the fetch, so failed refreshes don't leave rain
    /// "from 15:00" after 15:00 has come.
    @Test("Rain is now once its hour has begun, and an hour already over no longer counts")
    func fromTheClock() throws {
        let later = Self.now.addingTimeInterval(30 * 60)   // 15:10
        let outlook = try #require(RainOutlook(forecast(chance: 0.7, hour: 1), now: later))
        #expect(outlook.isUnderWay)
        // The 14:00 hour ended at 15:00.
        #expect(RainOutlook(forecast(chance: 0.9, hour: 0), now: later) == nil)
        // 17:00 is inside the window from 15:10, though not from the 14:40 fetch.
        #expect(RainOutlook(forecast(chance: 0.9, hour: 3), now: later) != nil)
    }

    @Test("The first wet hour wins, not the wettest")
    func firstWins() throws {
        var wet = forecast(chance: 0.6, hour: 1)
        wet.hourly[2].precipitationChance = 0.9
        #expect(try #require(RainOutlook(wet, now: Self.now)).chance == 0.6)
    }

    @Test("An hour starting beyond the window isn't this ride's rain")
    func beyondWindow() {
        // 17:00 starts 2 h 20 min after the 14:40 fetch.
        #expect(RainOutlook(forecast(chance: 0.9, hour: 3), now: Self.now) == nil)
    }

    @Test("A wet hour keeps its own symbol and name; any other sky reads as rain")
    func symbolAndName() throws {
        let snow = try #require(RainOutlook(forecast(chance: 0.7, hour: 1, condition: .snow), now: Self.now))
        #expect(snow.symbolName == "cloud.snow.fill")
        #expect(snow.name == "Snow")
        for condition in [WeatherCondition.cloudy, nil] {
            let cloudy = try #require(RainOutlook(forecast(chance: 0.7, hour: 1, condition: condition), now: Self.now))
            #expect(cloudy.symbolName == "cloud.rain.fill")
            #expect(cloudy.name == "Rain")
        }
    }
}
