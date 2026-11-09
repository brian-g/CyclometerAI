import SwiftUI

/// The forecast hour by hour across the ride (#149): one column per hour, the first labelled
/// "Now", each with its sky, temperature and chance of rain. A few hours spread across the row's
/// full width; a long ride with more than fit scrolls sideways instead.
struct HourlyForecastStrip: View {
    let hours: [WeatherReading]

    /// Follows the device's 12- or 24-hour setting, which iOS folds into the current locale.
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        // The first choice is used whenever its columns fit at their natural width; it then
        // stretches them to fill the row. Otherwise the same columns scroll.
        ViewThatFits(in: .horizontal) {
            columns(fillingWidth: true)
            ScrollView(.horizontal) {
                columns(fillingWidth: false)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func columns(fillingWidth: Bool) -> some View {
        HStack(alignment: .top, spacing: Spacing.lg) {
            ForEach(hours, id: \.date) { hour in
                column(hour, isNow: hour.date == hours.first?.date)
                    .frame(maxWidth: fillingWidth ? .infinity : nil)
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private func column(_ hour: WeatherReading, isNow: Bool) -> some View {
        VStack(spacing: Spacing.xs) {
            Text(isNow ? "Now" : hour.date.formatted(hourStyle))
                .font(.caption)
                .foregroundStyle(Color.cyTextSecondary)
            WeatherSymbol(reading: hour)
                .font(.title3)
                .frame(height: Spacing.xl)
            Text(hour.temperature.formatted(Self.temperatureStyle.locale(locale)))
                .font(.subheadline.weight(.semibold))
            if let chance = hour.precipitationChance {
                Text(chance, format: .percent.precision(.fractionLength(0)))
                    .font(.caption)
                    .foregroundStyle(Color.cyTextSecondary)
            }
        }
        .monospacedDigit()
        .frame(minWidth: Spacing.xxl)
        .accessibilityElement(children: .combine)
    }

    private var hourStyle: Date.FormatStyle {
        var style = Date.FormatStyle.dateTime.hour().locale(locale)
        style.timeZone = timeZone
        return style
    }

    /// "18°": whole degrees with no unit, as a forecast strip quotes them. The unit is the row's.
    static let temperatureStyle = Measurement<UnitTemperature>.FormatStyle(
        width: .narrow,
        usage: .weather,
        numberFormatStyle: .number.precision(.fractionLength(0))
    )
}

// MARK: - Previews

#Preview("Three hours") {
    List { HourlyForecastStrip(hours: Array(WeatherReading.fixtureHourly.prefix(4))) }
}

#Preview("A long ride, scrolls") {
    List { HourlyForecastStrip(hours: WeatherReading.fixtureHourly) }
}

#Preview("Night, 24-hour, dark") {
    List {
        HourlyForecastStrip(hours: WeatherReading.fixtureHourly.prefix(5).map {
            var hour = $0
            hour.isDaylight = false
            return hour
        })
    }
    .environment(\.locale, Locale(identifier: "de_DE"))
    .preferredColorScheme(.dark)
}
