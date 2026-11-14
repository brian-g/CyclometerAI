import SwiftUI

// MARK: - Weather Metrics

/// What the Weather sheet shows (#150): current conditions, the next hours, and WeatherKit's
/// attribution. An empty one is "no weather".
struct WeatherMetrics: Equatable {
    var forecast: AttributedForecast? = nil
    /// `RideWeatherFeature.State.forecastHours`: the strip's hours.
    var hours: [WeatherReading] = []
    /// The clock the metrics were read at, which is the strip's "Now". Only an empty sheet
    /// (no hours) leaves it at its default.
    var now: Date = .distantPast
    /// With no forecast to show, whether that is because the device is offline (#204).
    var isOffline = false
    /// The rider's direction of travel, for the wind's arrow; nil before they have moved.
    var course: Double? = nil
    var unit: UnitSystem = .metric
    /// Where the rider is, which the wind map centres on (#561); nil before the first fix.
    var riderCoordinate: RouteCoordinate? = nil
    /// The route being ridden, empty on a free ride. With one, the map shows the wind along it.
    var route: [RouteCoordinate] = []
    /// The forecast wind along the route ahead, W10's own reading first (#561). Empty on a free
    /// ride, where the map draws W10's reading as an even field instead.
    var routeWind: [WindSample] = []

    /// Whether the sheet has a wind map: a forecast, and a place to centre it.
    var hasWindMap: Bool { forecast != nil && riderCoordinate != nil }

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

extension RideWeatherFeature.State {
    /// The Weather sheet's inputs at `now`: nothing once the forecast is an hour old, and the strip
    /// from the hour under way. The rider's position and the route are the ride's, for the wind map.
    func metrics(at now: Date, unit: UnitSystem, rider: Coordinate? = nil,
                 route: [RouteCoordinate] = []) -> WeatherMetrics {
        let forecast = forecast(at: now)
        return WeatherMetrics(
            forecast: forecast,
            hours: forecast?.hours(within: Self.forecastWindow, from: now) ?? [],
            now: now,
            isOffline: forecast == nil && isLastFailureOffline,
            course: course,
            unit: unit,
            riderCoordinate: rider.map { RouteCoordinate(latitude: $0.latitude, longitude: $0.longitude, elevationMeters: nil) },
            route: route,
            routeWind: route.isEmpty ? [] : routeWind.samples
        )
    }
}

// MARK: - Weather Sheet

/// W10's sheet (#150).
///
/// `metrics` is called in this view's own `body`, not the presenter's `.sheet` builder, so the
/// open sheet follows the ride (see `RideMetricsSheet`, #144).
struct WeatherSheet: View {
    var metrics: (Date) -> WeatherMetrics = { _ in WeatherMetrics() }
    /// Each time the sheet opens: the ride samples the wind along the route ahead (#561).
    var onAppear: () -> Void = {}

    @State private var detent = PresentationDetent.medium

    var body: some View {
        NavigationStack {
            // Once a minute, as the card: the strip's "Now" moves on the hour.
            TimelineView(.everyMinute) { context in
                WeatherList(metrics: metrics(context.date))
            }
                .navigationTitle("Weather")
                .navigationBarTitleDisplayMode(.inline)
                .sheetCloseButton()
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .onAppear(perform: onAppear)
    }
}

/// The sheet's map, readings and forecast, apart from its navigation chrome so a snapshot can pin
/// them.
///
/// Generic over the map row, as `RouteDetailList` is: a live `Map` renders its tiles
/// asynchronously and can't be pixel-snapshotted reproducibly, so tests pass a placeholder of the
/// same height and the reference pins everything around it.
struct WeatherList<MapRow: View>: View {
    let metrics: WeatherMetrics
    let mapRow: MapRow

    @Environment(\.locale) private var locale

    var body: some View {
        List {
            // First, at S20's height (#561, Brian). Only with weather to show: the unavailable sheet
            // is unchanged.
            if metrics.hasWindMap {
                Section {
                    mapRow
                        .frame(height: RouteDetailView.mapHeight)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerMd, style: .continuous))
                        .listRowInsets(EdgeInsets())
                }
            }
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
                    if metrics.isOffline {
                        Text("Offline: Weather unavailable")
                    } else {
                        Text("Weather unavailable")
                    }
                }
            }
            if let forecast = metrics.forecast {
                // A forecast with no hour in the window would be an empty, padded row.
                Section {
                    if !metrics.hours.isEmpty {
                        HourlyForecastStrip(hours: metrics.hours, now: metrics.now)
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

extension WeatherList where MapRow == WeatherMap {
    init(metrics: WeatherMetrics) {
        self.init(metrics: metrics, mapRow: WeatherMap(metrics: metrics))
    }
}

// MARK: - Previews

#Preview("Weather") {
    WeatherList(metrics: WeatherMetrics(
        forecast: .fixture,
        hours: AttributedForecast.fixture.hours(within: RideWeatherFeature.State.forecastWindow),
        now: WeatherReading.fixtureNow,
        course: 90
    ))
}

#Preview("Offline") {
    WeatherList(metrics: WeatherMetrics(isOffline: true))
}

#Preview("No Weather — Dark") {
    WeatherList(metrics: WeatherMetrics())
        .preferredColorScheme(.dark)
}
