import SwiftUI

// MARK: - Weather Metrics

/// What the Weather sheet shows (#150): current conditions, the next hours, and WeatherKit's
/// attribution. An empty one is "no weather".
struct WeatherMetrics: Equatable {
    var forecast: AttributedForecast? = nil
    /// `RideWeatherFeature.State.forecastHours`: the strip's hours.
    var hours: [WeatherReading] = []
    /// The rider's direction of travel, for the wind's arrow; nil before they have moved.
    var course: Double? = nil
    var unit: UnitSystem = .metric

    var wind: MetricReading {
        guard let reading = forecast?.current else { return .missing }
        return MetricReading(
            value: reading.wholeWindSpeed(in: unit).formatted(.number.precision(.fractionLength(0))),
            unit: unit.speedLabel,
            spoken: reading.spokenWind(course: course, unit: unit)
        )
    }

    /// The compass point the wind blows from: "W". Missing in still air, which has none.
    var windFrom: MetricReading {
        guard let reading = forecast?.current, reading.wholeWindSpeed(in: unit) > 0 else { return .missing }
        let point = CompassPoint(degrees: reading.windDirection.converted(to: .degrees).value)
        return MetricReading(value: point.abbreviation, spoken: point.name)
    }

    func temperature(in temperatureUnit: UnitTemperature) -> MetricReading {
        guard let reading = forecast?.current else { return .missing }
        return MetricReading(
            value: reading.temperature.wholeDegrees(in: temperatureUnit).formatted(.number.precision(.fractionLength(0))),
            unit: temperatureUnit.symbol,
            spoken: reading.spokenTemperature(in: temperatureUnit)
        )
    }

    var humidity: MetricReading {
        guard let reading = forecast?.current else { return .missing }
        let percent = (reading.humidity * Self.percentPerUnit).rounded().formatted(.number.precision(.fractionLength(0)))
        return MetricReading(value: percent, unit: "%", spoken: "\(percent) percent")
    }

    private static let percentPerUnit = 100.0
}

extension ActiveRideFeature.State {
    /// The Weather sheet's inputs.
    var weatherMetrics: WeatherMetrics {
        WeatherMetrics(
            forecast: weather.forecast,
            hours: weather.forecastHours,
            course: weather.course,
            unit: unitSystem
        )
    }
}

// MARK: - Weather Sheet

/// W10's sheet (#150).
///
/// `metrics` is called in this view's own `body`, not the presenter's `.sheet` builder, so the
/// open sheet follows the ride (see `RideMetricsSheet`, #144).
struct WeatherSheet: View {
    var metrics: () -> WeatherMetrics = { WeatherMetrics() }

    @State private var detent = PresentationDetent.medium

    var body: some View {
        let metrics = metrics()
        NavigationStack {
            WeatherList(metrics: metrics)
                .navigationTitle("Weather")
                .navigationBarTitleDisplayMode(.inline)
                .sheetCloseButton()
        }
        .presentationDetents([.medium, .large], selection: $detent)
    }
}

/// The sheet's readings and forecast, apart from its navigation chrome so a snapshot can pin them.
struct WeatherList: View {
    let metrics: WeatherMetrics

    @Environment(\.locale) private var locale

    var body: some View {
        List {
            Section {
                if let reading = metrics.forecast?.current {
                    Label {
                        Text(reading.condition?.displayName ?? "Unknown")
                    } icon: {
                        WeatherSymbol(reading: reading)
                    }
                }
                ReadingColumns {
                    ReadingColumn("Wind", metrics.wind) {
                        if let reading = metrics.forecast?.current {
                            WindArrow(reading: reading, course: metrics.course, unit: metrics.unit, heroSize: .small)
                        }
                    }
                    ReadingColumn("From", metrics.windFrom)
                    ReadingColumn("Temperature", metrics.temperature(in: UnitTemperature(forLocale: locale, usage: .weather)))
                    ReadingColumn("Humidity", metrics.humidity)
                }
            } footer: {
                if metrics.forecast == nil {
                    Text("Weather unavailable")
                }
            }
            if let forecast = metrics.forecast {
                // A forecast with no hour in the window would be an empty, padded row.
                Section {
                    if !metrics.hours.isEmpty {
                        HourlyForecastStrip(hours: metrics.hours)
                    }
                } header: {
                    Text("Forecast")
                } footer: {
                    WeatherAttributionFooter(attribution: forecast.attribution)
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Weather") {
    WeatherList(metrics: WeatherMetrics(
        forecast: .fixture,
        hours: AttributedForecast.fixture.hours(within: RideWeatherFeature.State.forecastWindow),
        course: 90
    ))
}

#Preview("No Weather — Dark") {
    WeatherList(metrics: WeatherMetrics())
        .preferredColorScheme(.dark)
}
