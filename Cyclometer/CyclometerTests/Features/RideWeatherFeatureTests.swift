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
        #expect(store.state.forecast?.current == .fixture)
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

    /// A request WeatherKit never answers mustn't hold off every later one: past `refreshInterval`
    /// the next fix replaces it, and the stalled one's cancellation reports nothing.
    @Test("A request still out after ten minutes has stalled, and the next fix replaces it")
    func stalledRequestIsReplaced() async {
        let now = LockIsolated(Self.start)
        let isStalled = LockIsolated(true)
        let store = TestStore(initialState: RideWeatherFeature.State()) {
            RideWeatherFeature()
        } withDependencies: {
            $0.date = DateGenerator { now.value }
            $0.weatherClient.forecast = { coordinate in
                if isStalled.value { try await Task.never() }
                return try await WeatherClient.testValue.forecast(coordinate)
            }
        }
        await store.send(.locationUpdated(Self.fix())) {
            $0.course = 192
            $0.isFetching = true
            $0.lastAttemptAt = Self.start
        }

        now.setValue(Self.start.addingTimeInterval(RideWeatherFeature.refreshInterval - 1))
        await store.send(.locationUpdated(Self.fix()))

        let replaced = Self.start.addingTimeInterval(RideWeatherFeature.refreshInterval)
        now.setValue(replaced)
        isStalled.setValue(false)
        await store.send(.locationUpdated(Self.fix())) {
            $0.lastAttemptAt = replaced
        }
        await store.receive(.forecastLoaded(Self.forecast(at: replaced))) {
            $0.forecast = Self.forecast(at: replaced)
            $0.isFetching = false
        }
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
        #expect(store.state.forecast?.current == .fixture)

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
        #expect(store.state.forecast?.current == nil)
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

    /// #150 review: the widget asks once a minute, so a forecast goes at an hour old even when no
    /// fix arrives to clear it from state.
    @Test("A forecast is shown until it is an hour old, by the clock, and not after")
    func forecastHasAnHourCeiling() {
        var state = RideWeatherFeature.State()
        #expect(state.forecast(at: Self.start) == nil)

        state.forecast = Self.forecast(at: Self.start)
        #expect(state.forecast(at: Self.start.addingTimeInterval(RideWeatherFeature.maxAge - 1)) != nil)
        #expect(state.forecast(at: Self.start.addingTimeInterval(RideWeatherFeature.maxAge)) == nil)
        // A clock set back an hour doesn't keep it either.
        #expect(state.forecast(at: Self.start.addingTimeInterval(-RideWeatherFeature.maxAge)) == nil)
        #expect(RideWeatherFeature.maxAge == 3600)
    }
}
