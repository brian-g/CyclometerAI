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
    /// WeatherKit's default window, hourly from the current hour, in ascending date order.
    var hourlyForecast: @Sendable (RouteCoordinate) async throws -> [WeatherReading]
    var attribution: @Sendable () async throws -> WeatherSourceAttribution
}

enum WeatherClientError: Error, Equatable {
    /// `WeatherClient.unavailable`'s answer, for testing and previewing the failure path.
    case unavailable
}

extension WeatherClient: DependencyKey {
    static let liveValue = WeatherClient(
        current: { coordinate in
            try await logFailure("current conditions") {
                let current = try await WeatherService.shared.weather(for: location(coordinate), including: .current)
                return WeatherReading(current)
            }
        },
        hourlyForecast: { coordinate in
            try await logFailure("hourly forecast") {
                let hourly = try await WeatherService.shared.weather(for: location(coordinate), including: .hourly)
                return hourly.forecast.map(WeatherReading.init)
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
    static let testValue = WeatherClient(
        current: { _ in .fixture },
        hourlyForecast: { _ in WeatherReading.fixtureHourly },
        attribution: { .fixture }
    )

    static let previewValue = testValue

    static let unavailable = WeatherClient(
        current: { _ in throw WeatherClientError.unavailable },
        hourlyForecast: { _ in throw WeatherClientError.unavailable },
        attribution: { throw WeatherClientError.unavailable }
    )
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
            condition: WeatherCondition(current.condition),
            precipitationChance: nil
        )
    }

    init(_ hour: HourWeather) {
        self.init(
            date: hour.date,
            temperature: hour.temperature,
            windSpeed: hour.wind.speed,
            windDirection: hour.wind.direction,
            humidity: hour.humidity,
            condition: WeatherCondition(hour.condition),
            precipitationChance: hour.precipitationChance
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
