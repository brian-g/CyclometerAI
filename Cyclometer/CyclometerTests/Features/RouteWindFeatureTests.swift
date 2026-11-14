import ComposableArchitecture
import Foundation
import Testing
@testable import Cyclometer

/// #561 — the wind along a route, fetched point by point from a mock `WeatherClient`.
@MainActor
@Suite("RouteWindFeature")
struct RouteWindFeatureTests {

    nonisolated private static let now = WeatherReading.fixtureNow
    nonisolated private static let route = RouteFixtures.path(legs: [(0, 30_000)], spacingMeters: 100)

    /// The route sampled from its start at 5 m/s: 0, 10, 20 and 30 km, arriving 0, 33, 67 and 100
    /// minutes from now.
    nonisolated private static let points = WindSampling.points(
        coordinates: route, cumulative: RouteGeometry.cumulativeDistances(route), start: now, speedMPS: 5
    )
    private static let known = WindSample(coordinate: route[0], reading: .fixture)
    private static var ahead: [WindSamplePoint] { Array(points.dropFirst()) }

    /// Each point answers with the fixture forecast, its wind turned to `bearing(point)` so the
    /// samples can be told apart.
    private static func client(
        failing: Set<Int> = [],
        asked: LockIsolated<[RouteCoordinate]>? = nil
    ) -> WeatherClient {
        var client = WeatherClient.testValue
        client.forecast = { coordinate in
            asked?.withValue { $0.append(coordinate) }
            guard let index = points.firstIndex(where: { $0.coordinate == coordinate }) else {
                throw WeatherClientError.unavailable
            }
            if failing.contains(index) { throw WeatherClientError.unavailable }
            return WeatherForecast(current: reading(index, hour: 0), hourly: (0..<12).map { reading(index, hour: $0) })
        }
        return client
    }

    nonisolated private static func reading(_ index: Int, hour: Int) -> WeatherReading {
        var reading = WeatherReading.fixtureHourly[hour]
        reading.windDirection = Measurement(value: Double(index * 10 + hour), unit: .degrees)
        return reading
    }

    private func makeStore(_ client: WeatherClient) -> TestStoreOf<RouteWindFeature> {
        TestStore(initialState: RouteWindFeature.State()) {
            RouteWindFeature()
        } withDependencies: {
            $0.weatherClient = client
            $0.date = .constant(Self.now)
        }
    }

    @Test("Each point ahead takes the forecast hour the rider reaches it, after the known sample")
    func loadsInRouteOrder() async {
        let store = makeStore(Self.client())
        await store.send(.load(known: Self.known, ahead: Self.ahead)) {
            $0.requestedAt = Self.now
            $0.isFetching = true
            $0.samples = [Self.known]
        }
        // The fixture's hours start at 14:00 and the clock reads 14:40: 10 km is reached at 15:13
        // (the 15:00 hour), 20 km at 15:46, 30 km at 16:20.
        await store.receive(\.loaded) {
            $0.isFetching = false
            $0.samples = [
                Self.known,
                WindSample(coordinate: Self.points[1].coordinate, reading: Self.reading(1, hour: 1)),
                WindSample(coordinate: Self.points[2].coordinate, reading: Self.reading(2, hour: 1)),
                WindSample(coordinate: Self.points[3].coordinate, reading: Self.reading(3, hour: 2)),
            ]
        }
    }

    @Test("A point whose request fails is left out; the rest are drawn")
    func partialFailure() async {
        let store = makeStore(Self.client(failing: [2]))
        store.exhaustivity = .off
        await store.send(.load(known: Self.known, ahead: Self.ahead))
        await store.receive(\.loaded)
        #expect(store.state.samples.map(\.coordinate) == [Self.known.coordinate, Self.points[1].coordinate, Self.points[3].coordinate])
    }

    @Test("Every request failing leaves the known sample")
    func totalFailure() async {
        let store = makeStore(.unavailable)
        store.exhaustivity = .off
        await store.send(.load(known: Self.known, ahead: Self.ahead))
        await store.receive(\.loaded)
        #expect(store.state.samples == [Self.known])
        #expect(!store.state.isFetching)
    }

    @Test("A refetch keeps the last samples on screen until the new ones land")
    func refetchKeepsSamples() async {
        var state = RouteWindFeature.State()
        let old = [Self.known, WindSample(coordinate: Self.points[3].coordinate, reading: .fixture)]
        state.samples = old
        let store = TestStore(initialState: state) {
            RouteWindFeature()
        } withDependencies: {
            $0.weatherClient = Self.client()
            $0.date = .constant(Self.now)
        }
        store.exhaustivity = .off
        await store.send(.load(known: Self.known, ahead: Self.ahead)) {
            $0.samples = old
        }
        await store.receive(\.loaded)
        #expect(store.state.samples.count == 4)
    }

    @Test("Fresh for ten minutes either side of the request")
    func freshness() {
        var state = RouteWindFeature.State()
        #expect(!state.isFresh(at: Self.now))
        state.requestedAt = Self.now
        #expect(state.isFresh(at: Self.now.addingTimeInterval(RideWeatherFeature.refreshInterval - 1)))
        #expect(!state.isFresh(at: Self.now.addingTimeInterval(RideWeatherFeature.refreshInterval)))
        #expect(!state.isFresh(at: Self.now.addingTimeInterval(-RideWeatherFeature.refreshInterval)))
    }

    // MARK: - WeatherClient.wind(at:)

    @Test("wind(at:) asks once per point and answers in route order")
    func clientAsksEachPointOnce() async {
        let asked = LockIsolated<[RouteCoordinate]>([])
        let samples = await Self.client(asked: asked).wind(at: Self.ahead)
        #expect(Set(asked.value.map { "\($0.latitude),\($0.longitude)" }).count == 3)
        #expect(asked.value.count == 3)
        #expect(samples.map(\.coordinate) == Self.ahead.map(\.coordinate))
    }

    @Test("wind(at:) leaves out a point the rider reaches after the forecast ends")
    func pastTheForecast() async {
        var late = Self.ahead
        late[1].arrival = WeatherReading.fixtureDate.addingTimeInterval(13 * 3600)
        let samples = await Self.client().wind(at: late)
        #expect(samples.map(\.coordinate) == [late[0].coordinate, late[2].coordinate])
    }
}
