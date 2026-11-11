import Foundation
import Testing
@testable import Cyclometer

/// #150 — when W10 shows rain in place of the wind. The fixture forecast is fetched at 14:40, so
/// its window is the hours starting 14:00, 15:00 and 16:00, none of which reaches 50%.
@Suite("RainOutlook")
struct RainOutlookTests {

    private func forecast(chance: Double, hour: Int, condition: WeatherCondition? = .rain) -> AttributedForecast {
        var forecast = AttributedForecast.fixture
        forecast.hourly[hour].precipitationChance = chance
        forecast.hourly[hour].condition = condition
        return forecast
    }

    @Test("No hour in the window at 50% is no rain")
    func none() {
        #expect(RainOutlook(.fixture) == nil)
        #expect(RainOutlook(forecast(chance: 0.49, hour: 1)) == nil)
    }

    @Test("An hour at 50% within two hours is rain, from the start of that hour")
    func later() throws {
        let outlook = try #require(RainOutlook(forecast(chance: 0.5, hour: 2)))
        #expect(outlook.chance == 0.5)
        #expect(outlook.start == WeatherReading.fixtureDate.addingTimeInterval(2 * 3600))
        #expect(!outlook.isUnderWay)
    }

    @Test("The hour under way counts, and reads as now")
    func underWay() throws {
        let outlook = try #require(RainOutlook(forecast(chance: 0.8, hour: 0)))
        #expect(outlook.start == WeatherReading.fixtureDate)
        #expect(outlook.isUnderWay)
    }

    @Test("The first wet hour wins, not the wettest")
    func firstWins() throws {
        var wet = forecast(chance: 0.6, hour: 1)
        wet.hourly[2].precipitationChance = 0.9
        #expect(try #require(RainOutlook(wet)).chance == 0.6)
    }

    @Test("An hour starting beyond the window isn't this ride's rain")
    func beyondWindow() {
        // 17:00 starts 2 h 20 min after the 14:40 fetch.
        #expect(RainOutlook(forecast(chance: 0.9, hour: 3)) == nil)
    }

    @Test("A wet hour keeps its own symbol and name; any other sky reads as rain")
    func symbolAndName() throws {
        let snow = try #require(RainOutlook(forecast(chance: 0.7, hour: 1, condition: .snow)))
        #expect(snow.symbolName == "cloud.snow.fill")
        #expect(snow.name == "Snow")
        for condition in [WeatherCondition.cloudy, nil] {
            let cloudy = try #require(RainOutlook(forecast(chance: 0.7, hour: 1, condition: condition)))
            #expect(cloudy.symbolName == "cloud.rain.fill")
            #expect(cloudy.name == "Rain")
        }
    }
}
