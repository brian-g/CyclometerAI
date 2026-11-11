import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

/// #150 — W10 Weather: the wind with its arrow, the 2×1's temperature, and the rain state.
final class WeatherWidgetSnapshotTests: XCTestCase {

    private func makeWeather(
        reading: WeatherReading? = .fixture,
        course: Double? = 90,
        unit: UnitSystem = .metric,
        rain: RainOutlook? = nil,
        size: WidgetSize = .oneByOne,
        locale: String = "en_GB",
        scheme: ColorScheme = .light
    ) -> some View {
        WeatherWidget(reading: reading, course: course, unit: unit, rain: rain, size: size)
            .frame(width: size == .oneByOne ? 196 : 393, height: 96)
            // The temperature's unit and the rain's hour follow these: pinned, or another machine
            // records another image.
            .environment(\.locale, Locale(identifier: locale))
            .environment(\.timeZone, TimeZone(identifier: "UTC")!)
            .preferredColorScheme(scheme)
    }

    private func assertWidget(
        _ view: some View, size: WidgetSize = .oneByOne, dark: Bool = false,
        file: StaticString = #filePath, testName: String = #function, line: UInt = #line
    ) {
        // Grid slots: a 1×1 is half-width, a 2×1 full-width, both one row high.
        let canvas: SwiftUISnapshotLayout = .fixed(width: size == .oneByOne ? 196 : 393, height: 96)
        assertSnapshot(
            of: view,
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: dark ? .dark : .light)),
            file: file, testName: testName, line: line
        )
    }

    /// Rain from the fixture forecast's hour `hour` (0 is under way).
    private func rain(hour: Int, chance: Double, condition: WeatherCondition = .rain) -> RainOutlook? {
        var forecast = AttributedForecast.fixture
        forecast.hourly[hour].precipitationChance = chance
        forecast.hourly[hour].condition = condition
        return RainOutlook(forecast)
    }

    // MARK: - 1×1

    /// A westerly on a rider heading east: the arrow points up.
    func testWeatherOneByOneTailwind() {
        assertWidget(makeWeather())
    }

    /// Heading north, the same westerly crosses left to right.
    func testWeatherOneByOneCrosswindDark() {
        assertWidget(makeWeather(course: 0, scheme: .dark), dark: true)
    }

    func testWeatherOneByOneNoCourse() {
        assertWidget(makeWeather(course: nil))
    }

    func testWeatherOneByOneCalm() {
        var calm = WeatherReading.fixture
        calm.windSpeed = Measurement(value: 0.2, unit: .kilometersPerHour)
        assertWidget(makeWeather(reading: calm))
    }

    func testWeatherOneByOneNoWeather() {
        assertWidget(makeWeather(reading: nil, course: nil))
    }

    func testWeatherOneByOneRain() {
        assertWidget(makeWeather(rain: rain(hour: 1, chance: 0.7)))
    }

    func testWeatherOneByOneRainNowDark() {
        assertWidget(makeWeather(rain: rain(hour: 0, chance: 0.9, condition: .thunderstorm), scheme: .dark), dark: true)
    }

    // MARK: - 2×1

    func testWeatherTwoByOneHeadwind() {
        assertWidget(makeWeather(course: 270, size: .twoByOne), size: .twoByOne)
    }

    func testWeatherTwoByOneHeadwindDark() {
        assertWidget(makeWeather(course: 270, size: .twoByOne, scheme: .dark), size: .twoByOne, dark: true)
    }

    func testWeatherTwoByOneImperial() {
        assertWidget(makeWeather(unit: .imperial, size: .twoByOne, locale: "en_US"), size: .twoByOne)
    }

    func testWeatherTwoByOneNoWeather() {
        assertWidget(makeWeather(reading: nil, course: nil, size: .twoByOne), size: .twoByOne)
    }

    /// Rain as the hero, the wind stepped down beside the temperature.
    func testWeatherTwoByOneRain() {
        assertWidget(makeWeather(rain: rain(hour: 1, chance: 0.7), size: .twoByOne), size: .twoByOne)
    }

    /// The widest case: mph, a 12-hour "3 PM" and °F.
    func testWeatherTwoByOneRainImperial() {
        assertWidget(
            makeWeather(unit: .imperial, rain: rain(hour: 1, chance: 0.7), size: .twoByOne, locale: "en_US"),
            size: .twoByOne
        )
    }

    func testWeatherTwoByOneRainNowDark() {
        assertWidget(
            makeWeather(rain: rain(hour: 0, chance: 0.9, condition: .thunderstorm), size: .twoByOne, scheme: .dark),
            size: .twoByOne, dark: true
        )
    }
}
