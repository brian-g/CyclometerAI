import ComposableArchitecture
import Foundation
import Testing
@testable import Cyclometer

/// #152 — each fresh forecast where the rider is checks the route ahead for rain, and a wet check
/// raises the dashboard's silent banner for four seconds.
///
/// The rider is 6 km along a 100 km route at 14:40 (`fixtureNow`), riding at 6 m/s, so two hours
/// ahead is 49.2 km. The mock forecast is wet only in the hour starting 16:00 (hour 2): the first
/// point reached in it is 40.56 km along, 34.56 km ahead, at 16:16.
@MainActor
@Suite("ActiveRideFeature rain ahead")
struct ActiveRideRainAheadTests {

    private static let now = WeatherReading.fixtureNow
    private static let path = RouteFixtures.path(legs: [(0, 100_000)], spacingMeters: 100)
    private static let rider = Coordinate(latitude: 36.05, longitude: -80.0)

    /// Hourly forecast, dry except the hours in `wet`.
    nonisolated private static func hourly(wet: [Int: Double]) -> [WeatherReading] {
        WeatherReading.fixtureHourly.enumerated().map { hour, reading in
            var reading = reading
            reading.precipitationChance = wet[hour] ?? 0
            reading.condition = wet[hour] == nil ? .cloudy : .rain
            return reading
        }
    }

    /// W10's forecast where the rider is, fetched now.
    private static func forecast(wet: [Int: Double] = [:]) -> AttributedForecast {
        var forecast = AttributedForecast.fixture
        forecast.hourly = hourly(wet: wet)
        return forecast
    }

    /// Every point ahead answers with the same forecast, wet in `wet`'s hours, and is recorded.
    private static func client(wet: [Int: Double], asked: LockIsolated<[RouteCoordinate]>) -> WeatherClient {
        var client = WeatherClient.testValue
        client.forecast = { coordinate in
            asked.withValue { $0.append(coordinate) }
            return WeatherForecast(current: .fixture, hourly: hourly(wet: wet))
        }
        return client
    }

    /// A ride 6 km along the route (or `progress`), with the dashboard in front of the rider.
    private func state(
        ridden: Double = 6_000, progress: Double = 6_000, route: Bool = true, visible: Bool = true
    ) throws -> ActiveRideFeature.State {
        var state = ActiveRideFeature.State(recordingState: .active)
        state.isDashboardVisible = visible
        if route {
            state.navigation.activeRoute = try #require(NavigationRoute(coordinates: Self.path, maneuvers: []))
            state.navigation.progressMeters = progress
            state.route = RouteReference(id: UUID(0), name: "Out")
        }
        state.coordinate = Self.rider
        state.distanceMeters = ridden
        state.speedSampleCount = Int(ridden / 6)
        return state
    }

    private func makeStore(
        _ state: ActiveRideFeature.State,
        client: WeatherClient,
        clock: TestClock<Duration> = TestClock(),
        persistence: PersistenceClient = .mock()
    ) -> TestStoreOf<ActiveRideFeature> {
        let storage = FileStorage.inMemory
        let store = withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            TestStore(initialState: state) {
                ActiveRideFeature()
            } withDependencies: {
                $0.defaultFileStorage = storage
                $0.date = .constant(Self.now)
                $0.weatherClient = client
                $0.continuousClock = clock
                $0.persistenceClient = persistence
            }
        }
        store.exhaustivity = .off
        return store
    }

    /// The points the check should ask about: the route from 6 km to 49.2 km, the rider's own
    /// point left to W10's forecast.
    private static func expectedAhead(speedMPS: Double = 6) -> [WindSamplePoint] {
        Array(points(from: 6_000, speedMPS: speedMPS).dropFirst())
    }

    /// The route sampled from `progress` for two hours at `speedMPS`, the rider's point first.
    private static func points(from progress: Double, speedMPS: Double = 6) -> [WindSamplePoint] {
        WindSampling.points(
            coordinates: path, cumulative: RouteGeometry.cumulativeDistances(path),
            fromMeters: progress, toMeters: progress + speedMPS * RainOutlook.window, start: now, speedMPS: speedMPS
        )
    }

    @Test("A free ride's forecast checks nothing ahead")
    func freeRide() async throws {
        let asked = LockIsolated<[RouteCoordinate]>([])
        let store = makeStore(try state(route: false), client: Self.client(wet: [2: 0.9], asked: asked))
        await store.send(.weather(.forecastLoaded(Self.forecast(wet: [0: 0.9]))))
        await store.finish()
        #expect(asked.value.isEmpty)
        #expect(store.state.weather.rainAhead == nil, "no route, no banner, even with rain where the rider is")
    }

    /// Paused, locked, in the background or minimised: AppFeature says no one can see it.
    @Test("With the dashboard out of sight, a fresh forecast checks nothing ahead")
    func notVisible() async throws {
        let asked = LockIsolated<[RouteCoordinate]>([])
        let store = makeStore(try state(visible: false), client: Self.client(wet: [2: 0.9], asked: asked))
        await store.send(.weather(.forecastLoaded(Self.forecast(wet: [0: 0.9]))))
        await store.finish()
        #expect(asked.value.isEmpty)
        #expect(store.state.weather.rainAhead == nil)
    }

    /// Distances along a route the rider has left would mislead, and "Off route" matters more.
    @Test("Off route, a fresh forecast checks nothing ahead")
    func offRoute() async throws {
        let asked = LockIsolated<[RouteCoordinate]>([])
        var state = try state()
        state.navigation.isOffRoute = true
        let store = makeStore(state, client: Self.client(wet: [2: 0.9], asked: asked))
        await store.send(.weather(.forecastLoaded(Self.forecast(wet: [0: 0.9]))))
        await store.finish()
        #expect(asked.value.isEmpty)
        #expect(store.state.weather.rainAhead == nil)
    }

    /// Sampling always adds the finish, however close: within a kilometre of it, that point is
    /// where the rider is, and W10's own forecast answers for it.
    @Test("Within a kilometre of the finish, nothing ahead is asked about; the rider's own spot still counts")
    func nearTheFinish() async throws {
        let asked = LockIsolated<[RouteCoordinate]>([])
        let total = RouteGeometry.distanceMeters(Self.path)
        let store = makeStore(try state(progress: total - 3), client: Self.client(wet: [2: 0.9], asked: asked))
        await store.send(.weather(.forecastLoaded(Self.forecast(wet: [0: 0.6]))))
        await store.receive(.weather(.checkRainAhead(
            rider: try #require(Self.points(from: total - 3).first), ahead: []
        )))
        await store.receive(\.weather.rainAheadChecked)
        #expect(asked.value.isEmpty)
        #expect(store.state.weather.rainAhead?.isHere == true)
        await store.skipInFlightEffects()
    }

    @Test("With a route, only the stretch reached within two hours is asked about")
    func asksWithinTwoHours() async throws {
        let asked = LockIsolated<[RouteCoordinate]>([])
        let store = makeStore(try state(), client: Self.client(wet: [:], asked: asked))
        await store.send(.weather(.forecastLoaded(Self.forecast())))
        let ahead = Self.expectedAhead()
        await store.receive(\.weather.checkRainAhead)
        await store.receive(.weather(.rainAheadChecked(nil)))
        #expect(ahead.last?.distanceMeters == 49_200, "6 km plus two hours at 6 m/s")
        #expect(ahead.last?.arrival == Self.now.addingTimeInterval(RainOutlook.window))
        #expect(asked.value.count == ahead.count)
        #expect(Set(asked.value.map(\.latitude)) == Set(ahead.map(\.coordinate.latitude)))
        #expect(store.state.weather.rainAhead == nil, "dry ahead: no banner")
    }

    @Test("A wet check raises the banner, which clears after four seconds")
    func wetBanner() async throws {
        let clock = TestClock()
        let asked = LockIsolated<[RouteCoordinate]>([])
        let store = makeStore(try state(), client: Self.client(wet: [2: 0.7], asked: asked), clock: clock)
        await store.send(.weather(.forecastLoaded(Self.forecast())))
        await store.receive(\.weather.rainAheadChecked)
        let rain = try #require(store.state.weather.rainAhead)
        #expect(rain.chance == 0.7)
        #expect(abs(rain.distanceAheadMeters - 34_560) < 1)
        #expect(rain.bannerText(unitSystem: .metric) == "Rain 70% · 34.6 km ahead")
        await clock.advance(by: RideWeatherFeature.rainBannerDismissDelay)
        await store.receive(.weather(.rainBannerDismissed))
        #expect(store.state.weather.rainAhead == nil)
    }

    @Test("The next fresh forecast while the route ahead is still wet raises the banner again")
    func reFires() async throws {
        let clock = TestClock()
        let asked = LockIsolated<[RouteCoordinate]>([])
        let store = makeStore(try state(), client: Self.client(wet: [2: 0.7], asked: asked), clock: clock)
        for _ in 0..<2 {
            await store.send(.weather(.forecastLoaded(Self.forecast())))
            await store.receive(\.weather.rainAheadChecked)
            #expect(store.state.weather.rainAhead != nil)
            await clock.advance(by: RideWeatherFeature.rainBannerDismissDelay)
            await store.receive(.weather(.rainBannerDismissed))
        }
    }

    @Test("With every request ahead failing, rain where the rider is still raises it")
    func failuresAhead() async throws {
        let store = makeStore(try state(), client: .unavailable)
        await store.send(.weather(.forecastLoaded(Self.forecast(wet: [0: 0.6]))))
        await store.receive(\.weather.rainAheadChecked)
        #expect(store.state.weather.rainAhead?.isHere == true)
        await store.skipInFlightEffects()
    }

    @Test("With every request failing and the rider dry, there is no banner")
    func failuresDry() async throws {
        let store = makeStore(try state(), client: .unavailable)
        await store.send(.weather(.forecastLoaded(Self.forecast())))
        await store.receive(.weather(.rainAheadChecked(nil)))
        #expect(store.state.weather.rainAhead == nil)
    }

    /// S15's samples are the weather where the rider rode; the places ahead are not.
    @Test("Answers from the route ahead aren't recorded for the ride's weather summary")
    func samplesUntouched() async throws {
        let asked = LockIsolated<[RouteCoordinate]>([])
        let store = makeStore(try state(), client: Self.client(wet: [2: 0.7], asked: asked))
        await store.send(.weather(.forecastLoaded(Self.forecast())))
        await store.receive(\.weather.rainAheadChecked)
        #expect(store.state.weather.samples.count == 1, "only the rider's own forecast")
        await store.skipInFlightEffects()
    }

    /// Rain is informational: it must never read as a vehicle to the radar escalation (#135).
    @Test("A wet check leaves the radar alert level alone")
    func alertLevelUntouched() async throws {
        let asked = LockIsolated<[RouteCoordinate]>([])
        let initial = try state()
        let store = makeStore(initial, client: Self.client(wet: [2: 0.7], asked: asked))
        await store.send(.weather(.forecastLoaded(Self.forecast())))
        await store.receive(\.weather.rainAheadChecked)
        #expect(store.state.alertOrchestrator == initial.alertOrchestrator)
        await store.skipInFlightEffects()
    }

    /// The route has no estimate here (no summary to read), so it takes the default ride window.
    @Test("Before 5 km the route ahead is timed by the route's estimate")
    func estimateFirst() async throws {
        let asked = LockIsolated<[RouteCoordinate]>([])
        var persistence = PersistenceClient.mock()
        persistence.fetchRouteSummary = { _ in nil }
        let store = makeStore(
            try state(ridden: 1_000), client: Self.client(wet: [:], asked: asked), persistence: persistence
        )
        await store.send(.weather(.forecastLoaded(Self.forecast())))
        let speed = WindSampling.speedMPS(routeDistanceMeters: RouteGeometry.distanceMeters(Self.path), estimate: nil)
        let ahead = Self.expectedAhead(speedMPS: speed)
        await store.receive(\.weather.checkRainAhead)
        await store.receive(.weather(.rainAheadChecked(nil)))
        #expect(asked.value.count == ahead.count)
        #expect(Set(asked.value.map(\.latitude)) == Set(ahead.map(\.coordinate.latitude)))
    }
}
