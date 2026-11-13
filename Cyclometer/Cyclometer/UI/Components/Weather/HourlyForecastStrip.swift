import SwiftUI

/// The forecast hour by hour across the ride (#149): one column per hour, each with its sky,
/// temperature and chance of rain. The column whose hour contains `now` reads "Now" (#204), so a
/// forecast that starts later, or one left on screen past the hour, never labels the wrong hour.
/// A few hours spread across the row's full width; a long ride with more than fit scrolls sideways
/// instead.
struct HourlyForecastStrip: View {
    let hours: [WeatherReading]
    /// The moment "Now" is read against: the fetch time on a short-lived sheet (S05.1), or the
    /// clock on a screen that stays up (W10's sheet, S20).
    let now: Date

    /// Follows the device's 12- or 24-hour setting, which iOS folds into the current locale.
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    /// The symbols' row grows with Dynamic Type, as the `.title3` symbols in it do.
    @ScaledMetric(relativeTo: .title3) private var symbolHeight = Spacing.xl

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
                column(hour, isNow: Self.isNow(hour, at: now))
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
                .frame(height: symbolHeight)
            // Whole degrees with no unit, as a forecast strip quotes them: the row above has it.
            Text("\(hour.temperature.wholeDegrees(in: temperatureUnit), format: .number.precision(.fractionLength(0)))°")
                .font(.subheadline.weight(.semibold))
            if let chance = hour.precipitationChance {
                let percent = chance.formatted(.percent.precision(.fractionLength(0)))
                Text(percent)
                    .font(.caption)
                    .foregroundStyle(Color.cyTextSecondary)
                    .accessibilityLabel("\(percent) chance of rain")
            }
        }
        .monospacedDigit()
        .frame(minWidth: Spacing.xxl)
        .accessibilityElement(children: .combine)
    }

    /// Whether `hour` is the one under way at `now`: forecast hours are dated at their start.
    static func isNow(_ hour: WeatherReading, at now: Date) -> Bool {
        hour.date <= now && now < hour.date.addingTimeInterval(AttributedForecast.hourLength)
    }

    private var temperatureUnit: UnitTemperature { UnitTemperature(forLocale: locale, usage: .weather) }

    private var hourStyle: Date.FormatStyle {
        var style = Date.FormatStyle.dateTime.hour().locale(locale)
        style.timeZone = timeZone
        return style
    }
}

// MARK: - Previews

#Preview("Three hours") {
    List { HourlyForecastStrip(hours: Array(WeatherReading.fixtureHourly.prefix(4)), now: WeatherReading.fixtureNow) }
}

#Preview("A long ride, scrolls") {
    List { HourlyForecastStrip(hours: WeatherReading.fixtureHourly, now: WeatherReading.fixtureNow) }
}

#Preview("Starts later, no \"Now\"") {
    List { HourlyForecastStrip(hours: Array(WeatherReading.fixtureHourly.dropFirst(2).prefix(4)), now: WeatherReading.fixtureNow) }
}

#Preview("Night, 24-hour, dark") {
    List {
        HourlyForecastStrip(hours: WeatherReading.fixtureHourly.prefix(5).map {
            var hour = $0
            hour.isDaylight = false
            return hour
        }, now: WeatherReading.fixtureNow)
    }
    .environment(\.locale, Locale(identifier: "de_DE"))
    .preferredColorScheme(.dark)
}
