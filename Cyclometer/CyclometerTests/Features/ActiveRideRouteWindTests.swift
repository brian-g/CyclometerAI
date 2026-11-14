import ComposableArchitecture
import Foundation
import Testing
@testable import Cyclometer

/// #561 — W10's sheet sampling the wind along the route ahead when it opens.
@MainActor
@Suite("ActiveRideFeature route wind")
struct ActiveRideRouteWindTests {

    private static let now = WeatherReading.fixtureNow
    private static let path = RouteFixtures.path(legs: [(0, 40_000)], spacingMeters: 100)
    private static let rider = Coordinate(latitude: 36.05, longitude: -80.0)

    /// A ride `progress` metres along a 40 km route, having ridden `ridden` metres at 6 m/s, with
    /// W10's forecast fetched just now.
    private func state(progress: Double = 6_000, ridden: Double = 6_000,
                       route: Bool = true, forecast: Bool = true) throws -> ActiveRideFeature.State {
        var state = ActiveRideFeature.State(recordingState: .active)
        if route {
            state.navigation.activeRoute = try #require(NavigationRoute(coordinates: Self.path, maneuvers: []))
            state.navigation.progressMeters = progress
            state.route = RouteReference(id: UUID(0), name: "Out")
        }
        state.coordinate = Self.rider
        state.distanceMeters = ridden
        state.speedSampleCount = Int(ridden / 6)
        if forecast {
            state.weather.forecast = .fixture
        }
        return state
    }

    private func makeStore(_ state: ActiveRideFeature.State,
                           persistence: PersistenceClient = .mock()) -> TestStoreOf<ActiveRideFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            TestStore(initialState: state) {
                ActiveRideFeature()
            } withDependencies: {
                $0.defaultFileStorage = storage
                $0.date = .constant(Self.now)
                $0.weatherClient = .testValue
                $0.persistenceClient = persistence
            }
        }
    }

    private static var known: WindSample {
        WindSample(coordinate: RouteCoordinate(latitude: rider.latitude, longitude: rider.longitude, elevationMeters: nil),
                   reading: .fixture)
    }

    private static func ahead(from progress: Double, speedMPS: Double) -> [WindSamplePoint] {
        Array(WindSampling.points(
            coordinates: path, cumulative: RouteGeometry.cumulativeDistances(path),
            fromMeters: progress, start: now, speedMPS: speedMPS
        ).dropFirst())
    }

    @Test("A free ride's sheet asks for nothing")
    func freeRide() async throws {
        let store = makeStore(try state(route: false))
        await store.send(.weatherSheetOpened)
    }

    @Test("With no forecast there is no first sample, and nothing is asked")
    func noForecast() async throws {
        let store = makeStore(try state(forecast: false))
        await store.send(.weatherSheetOpened)
    }

    @Test("Past 5 km the route ahead is timed at this ride's average moving speed")
    func ownSpeed() async throws {
        let store = makeStore(try state(progress: 6_000, ridden: 6_000))
        store.exhaustivity = .off
        await store.send(.weatherSheetOpened)
        await store.receive(.weather(.routeWind(.load(known: Self.known, ahead: Self.ahead(from: 6_000, speedMPS: 6)))))
        await store.receive(\.weather.routeWind.loaded)
        #expect(store.state.weather.routeWind.samples.first == Self.known)
        #expect(store.state.weather.routeWind.samples.count == 5, "6 to 40 km: the rider and four ahead")
    }

    /// The route has no estimate here (no summary to read), so it takes the default ride window.
    @Test("Before 5 km the route ahead is timed by the route's estimate")
    func estimateFirst() async throws {
        var persistence = PersistenceClient.mock()
        persistence.fetchRouteSummary = { _ in nil }
        let store = makeStore(try state(progress: 1_000, ridden: 4_999), persistence: persistence)
        store.exhaustivity = .off
        await store.send(.weatherSheetOpened)
        await store.receive(.routeWindEstimated(nil))
        let speed = WindSampling.speedMPS(routeDistanceMeters: RouteGeometry.distanceMeters(Self.path), estimate: nil)
        await store.receive(.weather(.routeWind(.load(known: Self.known, ahead: Self.ahead(from: 1_000, speedMPS: speed)))))
        #expect(store.state.weather.routeWind.requestedAt == Self.now)
    }

    @Test("Sampled within ten minutes, reopening the sheet asks for nothing")
    func fresh() async throws {
        var state = try state()
        state.weather.routeWind.requestedAt = Self.now.addingTimeInterval(-5 * 60)
        let store = makeStore(state)
        await store.send(.weatherSheetOpened)
    }

    @Test("Free-ride metrics carry no route wind; a routed ride's carry the samples")
    func metrics() throws {
        var state = try state()
        state.weather.routeWind.samples = [Self.known]
        let free = state.weather.metrics(at: Self.now, unit: .metric, rider: Self.rider)
        #expect(free.routeWind.isEmpty)
        #expect(free.hasWindMap)
        let routed = state.weather.metrics(at: Self.now, unit: .metric, rider: Self.rider, route: Self.path)
        #expect(routed.routeWind == [Self.known])
        #expect(!state.weather.metrics(at: Self.now, unit: .metric).hasWindMap, "no rider, no map")
    }
}
