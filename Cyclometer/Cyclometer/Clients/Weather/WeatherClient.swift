import ComposableArchitecture
import CoreLocation
import Foundation
import os
import WeatherKit

// Stream live: Console.app / Xcode console, filter subsystem "xyz.acmeapps.ride".
private let logger = Logger.cyclometer(.network)

/// TCA dependency for Apple's WeatherKit (#148): current conditions and the hourly forecast at
/// a coordinate, and the attribution its terms require wherever that data is shown. Each call
/// sends the one coordinate it is given, with no account or identifier (PRD §12, Privacy).
///
/// Every failure is thrown, never trapped. That covers no network, and WeatherKit refusing an
/// app whose App ID lacks the WeatherKit App Service (`WeatherError.permissionDenied`). Callers
/// show their empty state on a throw.
struct WeatherClient: Sendable {
    var current: @Sendable (RouteCoordinate) async throws -> WeatherReading
    /// Current conditions and the hourly forecast in one WeatherKit request, for a screen that
    /// shows both (S05.1): one call against the quota rather than two.
    var forecast: @Sendable (RouteCoordinate) async throws -> WeatherForecast
    var attribution: @Sendable () async throws -> WeatherSourceAttribution
}

/// `WeatherClient.forecast`'s answer.
struct WeatherForecast: Equatable, Sendable {
    var current: WeatherReading
    /// WeatherKit's default window, hourly from the current hour, in ascending date order.
    var hourly: [WeatherReading]
}

enum WeatherClientError: Error, Equatable {
    /// `WeatherClient.unavailable`'s answer, for testing and previewing the failure path.
    case unavailable
}

extension WeatherClient: DependencyKey {
    static let liveValue: WeatherClient = WeatherClient(
        current: { coordinate in
            try await logFailure("current conditions") {
                let current = try await WeatherService.shared.weather(for: location(coordinate), including: .current)
                return WeatherReading(current)
            }
        },
        forecast: { coordinate in
            try await logFailure("forecast") {
                let (current, hourly) = try await WeatherService.shared.weather(
                    for: location(coordinate), including: .current, .hourly
                )
                return WeatherForecast(current: WeatherReading(current), hourly: hourly.forecast.map(WeatherReading.init))
            }
        },
        attribution: {
            try await logFailure("attribution") {
                WeatherSourceAttribution(try await WeatherService.shared.attribution)
            }
        }
    )

    /// Fixture data, so a feature built on weather is testable without the network or the
    /// entitlement. A test of the failure path overrides with `unavailable`.
    static let testValue: WeatherClient = WeatherClient(
        current: { _ in .fixture },
        forecast: { _ in WeatherForecast(current: .fixture, hourly: WeatherReading.fixtureHourly) },
        attribution: { .fixture }
    )

    static let previewValue: WeatherClient = testValue

    static let unavailable = WeatherClient(
        current: { _ in throw WeatherClientError.unavailable },
        forecast: { _ in throw WeatherClientError.unavailable },
        attribution: { throw WeatherClientError.unavailable }
    )
}

extension WeatherClient {
    /// The forecast at `coordinate` with its attribution, as S05.1 and W10 show it: one request for
    /// the weather, the attribution alongside, dated by `date` when both have answered. Throws when
    /// either fails, and the caller shows its empty state (failures are logged in `liveValue`).
    func attributedForecast(_ coordinate: RouteCoordinate, date: DateGenerator) async throws -> AttributedForecast {
        async let fetched = self.forecast(coordinate)
        async let attribution = self.attribution()
        let weather = try await fetched
        return AttributedForecast(
            current: weather.current,
            hourly: weather.hourly,
            attribution: try await attribution,
            fetchedAt: date.now
        )
    }
}

extension DependencyValues {
    var weatherClient: WeatherClient {
        get { self[WeatherClient.self] }
        set { self[WeatherClient.self] = newValue }
    }
}

// MARK: - Live implementation

extension WeatherClient {
    private static func location(_ coordinate: RouteCoordinate) -> CLLocation {
        CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    /// Logs a failed request, then rethrows it for the caller's empty state. A cancelled one (the
    /// effect torn down, or a refresh superseding it) is rethrown unlogged: it didn't fail.
    private static func logFailure<T>(
        _ request: String,
        _ body: () async throws -> T
    ) async throws -> T {
        do {
            return try await body()
        } catch {
            if !Task.isCancelled {
                logger.error("WeatherKit \(request, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
            throw error
        }
    }
}

private extension WeatherReading {
    init(_ current: CurrentWeather) {
        self.init(
            date: current.date,
            temperature: current.temperature,
            windSpeed: current.wind.speed,
            windDirection: current.wind.direction,
            humidity: current.humidity,
            condition: WeatherCondition(current.condition, cloudCover: current.cloudCover),
            precipitationChance: nil,
            isDaylight: current.isDaylight
        )
    }

    init(_ hour: HourWeather) {
        self.init(
            date: hour.date,
            temperature: hour.temperature,
            windSpeed: hour.wind.speed,
            windDirection: hour.wind.direction,
            humidity: hour.humidity,
            condition: WeatherCondition(hour.condition, cloudCover: hour.cloudCover),
            precipitationChance: hour.precipitationChance,
            isDaylight: hour.isDaylight
        )
    }
}

private extension WeatherSourceAttribution {
    init(_ attribution: WeatherAttribution) {
        self.init(
            serviceName: attribution.serviceName,
            legalPageURL: attribution.legalPageURL,
            combinedMarkLightURL: attribution.combinedMarkLightURL,
            combinedMarkDarkURL: attribution.combinedMarkDarkURL
        )
    }
}
