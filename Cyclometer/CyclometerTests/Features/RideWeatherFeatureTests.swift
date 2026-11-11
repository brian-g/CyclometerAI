import ComposableArchitecture
import Foundation
import Testing
@testable import Cyclometer

/// #150 — the weather during a ride: fetched on a location fix when due, kept through failures
/// until stale, with the rider's course held through a stop.
@MainActor
@Suite("RideWeatherFeature")
struct RideWeatherFeatureTests {

    private static let start = Date(timeIntervalSince1970: 1_000_000)

    private static func fix(heading: Double = 192, speed: Double = 8.5) -> LocationUpdate {
        LocationUpdate(
            coordinate: Coordinate(latitude: 43.0731, longitude: -89.4012),
            altitude: nil,
            speed: speed,
            horizontalAccuracy: 5,
            heading: heading,
            timestamp: start
        )
    }

    private static func forecast(at date: Date) -> AttributedForecast {
        AttributedForecast(current: .fixture, hourly: WeatherReading.fixtureHourly, attribution: .fixture, fetchedAt: date)
    }

    /// A store whose clock the test moves with `now`, and whose WeatherKit fails while `isOffline`.
    private func makeStore(
        _ state: RideWeatherFeature.State = RideWeatherFeature.State(),
        now: LockIsolated<Date>,
        isOffline: LockIsolated<Bool> = LockIsolated(false)
    ) -> TestStoreOf<RideWeatherFeature> {
        TestStore(initialState: state) {
            RideWeatherFeature()
        } withDependencies: {
            $0.date = DateGenerator { now.value }
            $0.weatherClient.forecast = { coordinate in
                try await (isOffline.value ? WeatherClient.unavailable : WeatherClient.testValue).forecast(coordinate)
            }
        }
    }

    @Test("The first fix fetches the weather where the rider is")
    func firstFixFetches() async {
        let store = makeStore(now: LockIsolated(Self.start))
        await store.send(.locationUpdated(Self.fix())) {
            $0.course = 192
            $0.isFetching = true
            $0.lastAttemptAt = Self.start
        }
        await store.receive(.forecastLoaded(Self.forecast(at: Self.start))) {
            $0.forecast = Self.forecast(at: Self.start)
            $0.isFetching = false
        }
        #expect(store.state.reading == .fixture)
    }

    @Test("A fresh forecast isn't refetched; one ten minutes old is")
    func refreshesWhenDue() async {
        let now = LockIsolated(Self.start)
        var state = RideWeatherFeature.State()
        state.forecast = Self.forecast(at: Self.start)
        state.lastAttemptAt = Self.start
        state.course = 192
        let store = makeStore(state, now: now)

        now.setValue(Self.start.addingTimeInterval(RideWeatherFeature.refreshInterval - 1))
        await store.send(.locationUpdated(Self.fix()))

        let due = Self.start.addingTimeInterval(RideWeatherFeature.refreshInterval)
        now.setValue(due)
        await store.send(.locationUpdated(Self.fix())) {
            $0.isFetching = true
            $0.lastAttemptAt = due
        }
        await store.receive(.forecastLoaded(Self.forecast(at: due))) {
            $0.forecast = Self.forecast(at: due)
            $0.isFetching = false
        }
    }

    @Test("A fix while a request is out doesn't start a second")
    func oneRequestAtATime() async {
        var state = RideWeatherFeature.State()
        state.isFetching = true
        state.course = 192
        let store = makeStore(state, now: LockIsolated(Self.start))
        await store.send(.locationUpdated(Self.fix()))
    }

    @Test("A failed request is retried after a minute, not on the next fix")
    func retriesAfterFailure() async {
        let now = LockIsolated(Self.start)
        let isOffline = LockIsolated(true)
        let store = makeStore(now: now, isOffline: isOffline)
        await store.send(.locationUpdated(Self.fix())) {
            $0.course = 192
            $0.isFetching = true
            $0.lastAttemptAt = Self.start
        }
        await store.receive(.fetchFailed) {
            $0.isFetching = false
            $0.didLastAttemptFail = true
        }

        now.setValue(Self.start.addingTimeInterval(RideWeatherFeature.retryInterval - 1))
        await store.send(.locationUpdated(Self.fix()))

        let retry = Self.start.addingTimeInterval(RideWeatherFeature.retryInterval)
        now.setValue(retry)
        isOffline.setValue(false)
        await store.send(.locationUpdated(Self.fix())) {
            $0.isFetching = true
            $0.lastAttemptAt = retry
        }
        await store.receive(.forecastLoaded(Self.forecast(at: retry))) {
            $0.forecast = Self.forecast(at: retry)
            $0.isFetching = false
            $0.didLastAttemptFail = false
        }
    }

    @Test("A failed refresh keeps the last forecast, until it is half an hour old")
    func staleForecastExpires() async {
        let now = LockIsolated(Self.start)
        var state = RideWeatherFeature.State()
        state.forecast = Self.forecast(at: Self.start)
        state.lastAttemptAt = Self.start
        state.course = 192
        let store = makeStore(state, now: now, isOffline: LockIsolated(true))

        let refresh = Self.start.addingTimeInterval(RideWeatherFeature.refreshInterval)
        now.setValue(refresh)
        await store.send(.locationUpdated(Self.fix())) {
            $0.isFetching = true
            $0.lastAttemptAt = refresh
        }
        await store.receive(.fetchFailed) {
            $0.isFetching = false
            $0.didLastAttemptFail = true
        }
        #expect(store.state.reading == .fixture)

        let stale = Self.start.addingTimeInterval(RideWeatherFeature.maxAge)
        now.setValue(stale)
        await store.send(.locationUpdated(Self.fix())) {
            $0.forecast = nil
            $0.isFetching = true
            $0.lastAttemptAt = stale
        }
        await store.receive(.fetchFailed) {
            $0.isFetching = false
        }
        #expect(store.state.reading == nil)
    }

    @Test("The course follows the rider while moving and holds through a stop")
    func courseHeldBelowTheFloor() async {
        var state = RideWeatherFeature.State()
        state.forecast = Self.forecast(at: Self.start)
        state.lastAttemptAt = Self.start
        let store = makeStore(state, now: LockIsolated(Self.start))

        await store.send(.locationUpdated(Self.fix(heading: 192))) { $0.course = 192 }
        await store.send(.locationUpdated(Self.fix(heading: 200))) { $0.course = 200 }
        // Below the floor GPS course is noise.
        await store.send(.locationUpdated(Self.fix(heading: 10, speed: NavigationFeature.courseSpeedFloorMPS - 0.1)))
        // CoreLocation's "no course".
        await store.send(.locationUpdated(Self.fix(heading: -1)))
        #expect(store.state.course == 200)
    }

    @Test("Rain within two hours is the widget's outlook; the sheet's strip covers three")
    func derivedFromForecast() {
        var state = RideWeatherFeature.State()
        #expect(state.rain == nil)
        #expect(state.forecastHours.isEmpty)

        var forecast = AttributedForecast.fixture
        forecast.hourly[1].precipitationChance = 0.7
        state.forecast = forecast
        #expect(state.rain?.chance == 0.7)
        // Fetched at 14:40: the hours starting 14:00 through 17:00.
        #expect(state.forecastHours.map(\.date) == (0..<4).map { WeatherReading.fixtureDate.addingTimeInterval(Double($0) * 3600) })
    }
}
