import Foundation
import Testing
@testable import Cyclometer

/// #152 — when the route ahead is wet enough for the dashboard's rain banner.
///
/// The rider is 5 km along the route at 14:40 (`fixtureNow`). The fixture's hours start at 14:00,
/// so an arrival at 15:20 falls in hour 1, 16:00 starts hour 2, and 16:40 is the window's end.
@Suite("RainAhead")
struct RainAheadTests {

    private static let now = WeatherReading.fixtureNow
    private static let riderMeters = 5_000.0

    /// An answer `distance` metres along the route, reached `minutes` after now. Its hours are dry
    /// except those in `wet`; its current conditions, like WeatherKit's, carry no chance at all.
    private static func answer(
        _ distance: Double, minutes: Double, wet: [Int: Double] = [:], condition: WeatherCondition = .rain
    ) -> PointForecast {
        let hourly = WeatherReading.fixtureHourly.enumerated().map { hour, reading in
            var reading = reading
            reading.precipitationChance = wet[hour] ?? 0
            reading.condition = wet[hour] == nil ? .cloudy : condition
            return reading
        }
        return PointForecast(
            point: WindSamplePoint(
                coordinate: RouteCoordinate(latitude: distance / 100_000, longitude: 0, elevationMeters: nil),
                distanceMeters: distance,
                arrival: now.addingTimeInterval(minutes * 60)
            ),
            forecast: WeatherForecast(current: .fixture, hourly: hourly)
        )
    }

    private static func rider(wet: [Int: Double] = [:]) -> PointForecast {
        answer(riderMeters, minutes: 0, wet: wet)
    }

    @Test("Nothing at 50% along the window is no rain")
    func dry() {
        #expect(RainAhead(rider: Self.rider(), ahead: [Self.answer(15_000, minutes: 40)]) == nil)
        #expect(RainAhead(rider: Self.rider(), ahead: [Self.answer(15_000, minutes: 40, wet: [1: 0.49])]) == nil)
    }

    @Test("A point ahead at 50% in the hour the rider reaches it is rain there")
    func wetAhead() throws {
        let rain = try #require(RainAhead(
            rider: Self.rider(),
            ahead: [Self.answer(15_000, minutes: 40), Self.answer(25_000, minutes: 80, wet: [2: 0.5])]
        ))
        #expect(rain.chance == 0.5)
        #expect(rain.distanceAheadMeters == 20_000, "from the rider, not from the route's start")
        #expect(rain.arrival == Self.now.addingTimeInterval(80 * 60))
        #expect(!rain.isHere)
    }

    @Test("Rain in another hour at that point doesn't count: only the hour of arrival")
    func onlyTheArrivalHour() {
        let ahead = [Self.answer(15_000, minutes: 40, wet: [0: 0.9, 2: 0.9])]
        #expect(RainAhead(rider: Self.rider(), ahead: ahead) == nil, "reached at 15:20, in the dry hour 1")
    }

    /// The gotcha: current conditions never carry a chance, so the hour under way must come from
    /// the hourly forecast.
    @Test("Where the rider is, the hour under way is read from the hourly forecast")
    func here() throws {
        let rain = try #require(RainAhead(rider: Self.rider(wet: [0: 0.6]), ahead: []))
        #expect(rain.isHere)
        #expect(rain.distanceAheadMeters == 0)
        #expect(rain.arrival == Self.now)
    }

    @Test("A point reached within the hour under way reads that hour too")
    func aheadInTheHourUnderWay() throws {
        let rain = try #require(RainAhead(rider: Self.rider(), ahead: [Self.answer(8_000, minutes: 10, wet: [0: 0.7])]))
        #expect(rain.distanceAheadMeters == 3_000)
    }

    @Test("A point reached after the window's two hours doesn't count; one at its end does")
    func window() {
        #expect(RainAhead(rider: Self.rider(), ahead: [Self.answer(35_000, minutes: 121, wet: [2: 0.9])]) == nil)
        #expect(RainAhead(rider: Self.rider(), ahead: [Self.answer(35_000, minutes: 120, wet: [2: 0.9])]) != nil)
    }

    @Test("A point reached after its forecast ends doesn't count")
    func pastTheForecast() {
        #expect(RainAhead(rider: Self.rider(), ahead: [Self.answer(35_000, minutes: 12 * 60, wet: [11: 0.9])]) == nil)
    }

    @Test("The first wet place wins over a wetter one further on")
    func firstWins() throws {
        let rain = try #require(RainAhead(
            rider: Self.rider(),
            ahead: [Self.answer(15_000, minutes: 40, wet: [1: 0.55]), Self.answer(25_000, minutes: 80, wet: [2: 0.95])]
        ))
        #expect(rain.chance == 0.55)
        #expect(rain.distanceAheadMeters == 10_000)
    }

    @Test("Snow and thunderstorms are named as W10 names them")
    func names() throws {
        let snow = try #require(RainAhead(rider: Self.rider(), ahead: [Self.answer(15_000, minutes: 40, wet: [1: 0.6], condition: .snow)]))
        #expect(snow.name == "Snow")
        #expect(snow.symbolName == RainOutlook.symbolName(for: .snow, isDaylight: true))
        var storm = snow
        storm.condition = .thunderstorm
        #expect(storm.name == RainOutlook.name(for: .thunderstorm))
    }

    @Test("The banner reads the chance and how far ahead, or here")
    func bannerText() {
        let ahead = RainAhead(chance: 0.7, condition: .rain, isDaylight: true, distanceAheadMeters: 18_400, arrival: Self.now)
        #expect(ahead.bannerText(unitSystem: .metric) == "Rain 70% · 18.4 km ahead")
        #expect(ahead.bannerText(unitSystem: .imperial) == "Rain 70% · 11.4 mi ahead")
        var near = ahead
        near.distanceAheadMeters = RainAhead.hereMeters
        #expect(near.bannerText(unitSystem: .metric) == "Rain 70% · 1.0 km ahead", "the nearest a point ahead can be")
        var here = ahead
        here.distanceAheadMeters = 0
        #expect(here.bannerText(unitSystem: .metric) == "Rain 70% · here")
    }

    /// #568: VoiceOver reads W10's rain phrasing, the distance in words, never "km" or "·".
    @Test("VoiceOver reads the chance and how far ahead in words, or here")
    func spokenText() {
        let ahead = RainAhead(chance: 0.7, condition: .rain, isDaylight: true, distanceAheadMeters: 18_400, arrival: Self.now)
        #expect(ahead.spokenText(unitSystem: .metric) == "Rain, 70% chance, 18.4 kilometers ahead")
        #expect(ahead.spokenText(unitSystem: .imperial) == "Rain, 70% chance, 11.4 miles ahead")
        var here = ahead
        here.distanceAheadMeters = 0
        #expect(here.spokenText(unitSystem: .metric) == "Rain, 70% chance, here")
    }
}
