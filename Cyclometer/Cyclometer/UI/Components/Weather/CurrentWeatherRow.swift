import SwiftUI

/// Current conditions as one list row (#149): the sky and its name, the wind under it, and the
/// temperature trailing. Shared with S20's Current Weather section (#204).
///
/// The temperature is a small `HeroNumber`, in the locale's weather unit (`.weather` usage), which
/// honours iOS's own Temperature setting rather than the app's metric/imperial choice:
/// `UnitSystem.imperial` covers the UK, which reads miles per hour but degrees Celsius.
struct CurrentWeatherRow: View {
    let reading: WeatherReading
    let unit: UnitSystem

    @Environment(\.locale) private var locale

    var body: some View {
        // The last baseline, the wind line's: the number sits on the row's bottom line and spans both.
        HStack(alignment: .lastTextBaseline) {
            Label {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(reading.condition?.displayName ?? "Unknown")
                    WindLabel(reading: reading, unit: unit)
                }
            } icon: {
                WeatherSymbol(reading: reading)
            }
            Spacer()
            let temperatureUnit = UnitTemperature(forLocale: locale, usage: .weather)
            HeroNumber(reading.temperature.wholeDegrees(in: temperatureUnit), decimals: 0, unit: temperatureUnit.symbol)
                .heroNumberSize(.small)
                .layout(.horizontal)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The wind: an arrow pointing the way it blows, the compass point it comes from, and its speed in
/// the rider's units ("W 14 km/h"). "Calm" when the speed rounds to nothing in those units: an arrow
/// and a compass point for still air would point somewhere for no reason.
struct WindLabel: View {
    let reading: WeatherReading
    let unit: UnitSystem

    var body: some View {
        let from = reading.windDirection.converted(to: .degrees).value
        let point = CompassPoint(degrees: from)
        let speed = reading.wholeWindSpeed(in: unit)
        Group {
            if speed == 0 {
                Text("Calm")
                    .accessibilityLabel("Wind calm")
            } else {
                Label {
                    Text("\(point.abbreviation) \(speed, format: .number.precision(.fractionLength(0))) \(unit.speedLabel)")
                } icon: {
                    // Downwind: a westerly blows toward the east.
                    Image(systemName: "arrow.up")
                        .rotationEffect(.degrees(from + Self.downwind))
                }
                .labelIconToTitleSpacing(Spacing.xs)
                .accessibilityLabel("Wind from \(point.name), \(speed, format: .number.precision(.fractionLength(0))) \(unit.speedLabel)")
            }
        }
        .font(.subheadline)
        .foregroundStyle(Color.cyTextSecondary)
        .monospacedDigit()
    }

    /// A bearing names where the wind comes from; the arrow shows where it goes.
    private static let downwind = 180.0
}

/// A reading's sky as an SF Symbol, with its night form after dark.
///
/// Hierarchical in a text token rather than multicolor: multicolor draws clouds and moons in a fixed
/// white, which vanishes on a light list row (#149).
struct WeatherSymbol: View {
    let reading: WeatherReading

    var body: some View {
        Image(systemName: reading.condition?.symbolName(isDaylight: reading.isDaylight)
              ?? WeatherCondition.unknownSymbolName)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Color.cyTextSecondary)
            .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview("Day, metric") {
    List { CurrentWeatherRow(reading: .fixture, unit: .metric) }
}

#Preview("Night, imperial") {
    var night = WeatherReading.fixture
    night.condition = .clear
    night.isDaylight = false
    return List { CurrentWeatherRow(reading: night, unit: .imperial) }
        .environment(\.locale, Locale(identifier: "en_US"))
}

#Preview("Unknown condition, dark") {
    var unknown = WeatherReading.fixture
    unknown.condition = nil
    return List { CurrentWeatherRow(reading: unknown, unit: .metric) }
        .preferredColorScheme(.dark)
}
