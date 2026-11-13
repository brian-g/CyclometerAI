import SwiftUI

/// S20's Weather section (#204): the conditions at the route's start and the hours a ride on it
/// would see, or why there are none. Its footer carries WeatherKit's attribution, shown only with
/// WeatherKit data above it.
///
/// S05.1's `StartSheetWeatherSection` in shape. Its unavailable states differ: the route's start is
/// a fixed coordinate, so there is no location to turn on, but being offline is named.
struct RouteWeatherSection: View {
    let weather: RouteWeather
    /// `RouteDetailFeature.State.forecastHours(at:)`: the strip's hours.
    let hours: [WeatherReading]
    /// The strip's "Now".
    let now: Date
    let unit: UnitSystem

    var body: some View {
        Section {
            switch weather {
            case .loading:
                centered { ProgressView() }
            case .unavailable(.offline):
                centered { message("Offline: Weather unavailable") }
            case .unavailable(.failed):
                centered { message("Weather unavailable") }
            case .loaded(let forecast):
                CurrentWeatherRow(reading: forecast.current, unit: unit)
                // A forecast with no hour in the window would be an empty, padded row.
                if !hours.isEmpty {
                    HourlyForecastStrip(hours: hours, now: now)
                }
            }
        } header: {
            Text("Weather")
        } footer: {
            if case .loaded(let forecast) = weather {
                WeatherAttributionFooter(attribution: forecast.attribution)
            }
        }
    }

    /// A key, not a `String`: `Text(String)` line-breaks by the device language (#430).
    private func message(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .foregroundStyle(Color.cyTextSecondary)
            .multilineTextAlignment(.center)
    }

    /// Centred, as S05.1's messages are.
    private func centered(@ViewBuilder _ content: () -> some View) -> some View {
        HStack {
            Spacer()
            content()
            Spacer()
        }
    }
}

// MARK: - Previews

#Preview("Loaded, metric") {
    List {
        RouteWeatherSection(
            weather: .loaded(.fixture),
            hours: AttributedForecast.fixture.rideHours(estimate: nil, from: WeatherReading.fixtureNow),
            now: WeatherReading.fixtureNow,
            unit: .metric
        )
    }
}

#Preview("Loaded, imperial, dark") {
    List {
        RouteWeatherSection(
            weather: .loaded(.fixture),
            hours: AttributedForecast.fixture.rideHours(estimate: 2 * 3600, from: WeatherReading.fixtureNow),
            now: WeatherReading.fixtureNow,
            unit: .imperial
        )
    }
    .environment(\.locale, Locale(identifier: "en_US"))
    .preferredColorScheme(.dark)
}

#Preview("Loading") {
    List { RouteWeatherSection(weather: .loading, hours: [], now: WeatherReading.fixtureNow, unit: .metric) }
}

#Preview("Offline") {
    List { RouteWeatherSection(weather: .unavailable(.offline), hours: [], now: WeatherReading.fixtureNow, unit: .metric) }
}

#Preview("Unavailable") {
    List { RouteWeatherSection(weather: .unavailable(.failed), hours: [], now: WeatherReading.fixtureNow, unit: .metric) }
}
