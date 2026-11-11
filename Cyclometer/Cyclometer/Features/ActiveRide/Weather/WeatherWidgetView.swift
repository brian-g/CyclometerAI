import SwiftUI

// MARK: - W10 Weather Widget

/// W10 — Weather (#150): the wind's speed, with an arrow showing which way it blows relative to the
/// rider's direction of travel — up is a tailwind, down a headwind. The 2×1 adds the temperature.
///
/// With rain forecast (`RainOutlook`) the hero is that instead: its chance and the hour it starts.
/// The 2×1 keeps the wind, smaller, beside the temperature; the 1×1's wind is still in the sheet.
///
/// Always on the dashboard: with no weather (no location, WeatherKit unreachable, or a reading
/// gone stale) it reads "—". The arrow needs a course, so it is absent until the rider has moved,
/// and in still air, where it would point somewhere for no reason.
struct WeatherWidget: View {
    let reading: WeatherReading?
    /// The rider's direction of travel, degrees from true north; nil before they have moved.
    let course: Double?
    let unit: UnitSystem
    /// Rain within the next hours, shown in place of the wind; nil with none forecast.
    var rain: RainOutlook? = nil
    /// The Weather sheet's data. A closure so the card never reads the forecast itself; only the
    /// open sheet does, in its own body (#144).
    var metrics: (Date) -> WeatherMetrics = { _ in WeatherMetrics() }
    var size: WidgetSize = .oneByOne   // only .oneByOne / .twoByOne used by W10

    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        Group {
            switch size {
            case .oneByOne, .twoByTwo: oneByOneContent
            case .twoByOne:            twoByOneContent
            }
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetSymbol(size == .oneByOne && rain == nil ? "wind" : nil)
        .overlay(alignment: .bottomTrailing) {
            // The 1×1 has no room beside its hero, so the rain's hour takes the symbol's corner.
            if size == .oneByOne, let rain {
                rainStart(rain).padding(Spacing.sm)
            }
        }
        .background(Color.cyBgSecondary)
        .widgetDetail(label: WeatherDashboardWidget.title, value: accessibilityValue) {
            WeatherSheet(metrics: metrics)
        }
    }

    // MARK: - Layout Variants

    private var oneByOneContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel(WeatherDashboardWidget.title)
            if let rain { rainHero(rain) } else { windHero(.medium) }
            Spacer()
        }
    }

    private var twoByOneContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel(WeatherDashboardWidget.title)
            // The last baseline: the temperature sits on the wind's digits (UX.md §Alignment).
            HStack(alignment: .lastTextBaseline, spacing: Spacing.lg) {
                if let rain {
                    rainHero(rain)
                    rainStart(rain)
                } else {
                    windHero(.medium)
                }
                Spacer()
                if let reading {
                    // With rain as the hero the wind steps down beside the temperature.
                    if rain != nil { windHero(.small) }
                    let temperatureUnit = UnitTemperature(forLocale: locale, usage: .weather)
                    HeroNumber(reading.temperature.wholeDegrees(in: temperatureUnit), decimals: 0, unit: temperatureUnit.symbol)
                        .heroNumberSize(.small)
                }
            }
            Spacer()
        }
    }

    // MARK: - Sub-Views

    @ViewBuilder
    private func windHero(_ heroSize: HeroSize) -> some View {
        if let reading {
            HeroNumber(reading.wholeWindSpeed(in: unit), decimals: 0, unit: unit.speedLabel)
                .heroNumberSize(heroSize)
                .heroAccessory(.capCenter) {
                    WindArrow(reading: reading, course: course, unit: unit, heroSize: heroSize)
                }
        } else {
            HeroNumber("—", unit: "").heroNumberSize(heroSize)
        }
    }

    /// The rain's chance as the hero, "70 %", behind its symbol.
    private func rainHero(_ rain: RainOutlook) -> some View {
        HeroNumber(rain.chance * Self.percentPerUnit, decimals: 0, unit: "%")
            .heroNumberSize(.medium)
            .heroAccessory(.capCenter) {
                Image(systemName: rain.symbolName)
                    .symbolRenderingMode(.hierarchical)
                    .font(.title)
                    .dynamicTypeSize(...DynamicTypeSize.cyCaptionMax)
                    .foregroundStyle(Color.cyPrimaryDark)
            }
    }

    /// When the rain starts: "Now", or the hour — "3 PM" on a 12-hour clock, "15:00" on a 24-hour
    /// one, where a bare "15" beside the chance would read as a second number. In the 1×1's corner,
    /// and after the chance on the 2×1.
    private func rainStart(_ rain: RainOutlook) -> some View {
        Text(rainStartText(rain))
            .font(.footnote)
            .dynamicTypeSize(...DynamicTypeSize.cyCaptionMax)
            .foregroundStyle(Color.cyTextSecondary)
    }

    private func rainStartText(_ rain: RainOutlook) -> String {
        guard !rain.isUnderWay else { return "Now" }
        let isTwentyFourHour = [.zeroToTwentyThree, .oneToTwentyFour].contains(locale.hourCycle)
        var style = (isTwentyFourHour
            ? Date.FormatStyle.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
            : Date.FormatStyle.dateTime.hour()
        ).locale(locale)
        style.timeZone = timeZone
        return rain.start.formatted(style)
    }

    private static let percentPerUnit = 100.0

    /// What VoiceOver reads after "Weather" (#361): "14 kilometers per hour, headwind, 18 degrees
    /// Celsius"; with rain forecast, "Rain, 70 percent chance, from 3 PM"; or that there is no reading.
    var accessibilityValue: String {
        if let rain {
            let percent = rain.chance.formatted(.percent.precision(.fractionLength(0)))
            let spokenRain = "\(rain.name), \(percent) chance, \(rain.isUnderWay ? "now" : "from \(rainStartText(rain))")"
            // The 2×1 still shows the wind and temperature; the 1×1 shows the rain alone.
            guard size == .twoByOne, let reading else { return spokenRain }
            return [spokenRain, spokenConditions(reading)].joined(separator: ", ")
        }
        guard let reading else { return MetricReading.missing.spoken }
        return spokenConditions(reading)
    }

    private func spokenConditions(_ reading: WeatherReading) -> String {
        let temperatureUnit = UnitTemperature(forLocale: locale, usage: .weather)
        return [
            reading.spokenWind(course: course, unit: unit),
            reading.spokenTemperature(in: temperatureUnit),
        ].joined(separator: ", ")
    }
}

// MARK: - Wind Arrow

/// The wind relative to the rider (#150): an arrow pointing the way it blows, where up is the
/// rider's direction of travel. Nothing without a course, or in still air.
struct WindArrow: View {
    let reading: WeatherReading
    let course: Double?
    let unit: UnitSystem
    /// The hero it sits before: W9's turn glyph beside a medium one, a text-sized arrow beside a
    /// small one (W10's 2×1 in rain, and the sheet).
    var heroSize: HeroSize = .medium

    var body: some View {
        if let course, reading.wholeWindSpeed(in: unit) > 0 {
            Image(systemName: "arrow.up")
                .font(heroSize == .small ? .title3.weight(.semibold) : .cyTurnGlyphCompact)
                .dynamicTypeSize(...DynamicTypeSize.cyCaptionMax)
                .foregroundStyle(Color.cyPrimaryDark)
                .rotationEffect(.degrees(RelativeWind.arrowRotation(
                    windFrom: reading.windDirection.converted(to: .degrees).value,
                    course: course
                )))
        }
    }
}

// MARK: - Wording

extension WeatherReading {
    /// "14 kilometers per hour, headwind"; without a course, the compass point instead ("from the
    /// west"); "Wind calm" in still air.
    func spokenWind(course: Double?, unit: UnitSystem) -> String {
        guard wholeWindSpeed(in: unit) > 0 else { return "Wind calm" }
        let from = windDirection.converted(to: .degrees).value
        let speed = unit.spokenSpeed(fromMPS: windSpeed.converted(to: .metersPerSecond).value, fractionLength: 0)
        let direction = course.map { RelativeWind(windFrom: from, course: $0).name }
            ?? "from the \(CompassPoint(degrees: from).name)"
        return "\(speed), \(direction)"
    }

    /// "18 degrees Celsius".
    func spokenTemperature(in unit: UnitTemperature) -> String {
        Measurement(value: temperature.wholeDegrees(in: unit), unit: unit).formatted(
            .measurement(width: .wide, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))
        )
    }
}

// MARK: - Previews

#Preview("1×1 Tailwind") {
    WeatherWidget(reading: .fixture, course: 90, unit: .metric)
        .frame(width: 196, height: 96)
}

#Preview("1×1 No Weather") {
    WeatherWidget(reading: nil, course: nil, unit: .metric)
        .frame(width: 196, height: 96)
}

#Preview("1×1 Rain Forecast") {
    WeatherWidget(reading: .fixture, course: 90, unit: .metric, rain: .previewLater)
        .frame(width: 196, height: 96)
}

#Preview("2×1 Rain Now") {
    WeatherWidget(reading: .fixture, course: 90, unit: .metric, rain: .previewNow, size: .twoByOne)
        .frame(width: 393, height: 96)
}

#Preview("2×1 Headwind") {
    WeatherWidget(reading: .fixture, course: 270, unit: .metric, size: .twoByOne)
        .frame(width: 393, height: 96)
}

#Preview("2×1 No Course, imperial") {
    WeatherWidget(reading: .fixture, course: nil, unit: .imperial, size: .twoByOne)
        .frame(width: 393, height: 96)
        .environment(\.locale, Locale(identifier: "en_US"))
}

#Preview("2×1 No Weather — Dark") {
    WeatherWidget(reading: nil, course: nil, unit: .metric, size: .twoByOne)
        .frame(width: 393, height: 96)
        .preferredColorScheme(.dark)
}

private extension RainOutlook {
    /// Rain from the fixture forecast's second hour.
    static var previewLater: RainOutlook? {
        var forecast = AttributedForecast.fixture
        forecast.hourly[1].precipitationChance = 0.7
        forecast.hourly[1].condition = .rain
        return RainOutlook(forecast, now: WeatherReading.fixtureNow)
    }

    /// A thunderstorm in the hour under way.
    static var previewNow: RainOutlook? {
        var forecast = AttributedForecast.fixture
        forecast.hourly[0].precipitationChance = 0.9
        forecast.hourly[0].condition = .thunderstorm
        return RainOutlook(forecast, now: WeatherReading.fixtureNow)
    }
}
