import ComposableArchitecture
import Foundation

/// The weather where the rider is, during a ride (#150): what W10 and its sheet show.
///
/// Driven by the ride's location fixes rather than a timer, as W21's `SunsetFix` is: each fix
/// keeps the rider's course, and fetches when the forecast is due. No fix means no fetch, so a
/// ride without location shows W10's empty state and never raises a prompt.
@Reducer
struct RideWeatherFeature {
    @Dependency(\.weatherClient) var weatherClient
    @Dependency(\.date) var date

    /// How old a forecast gets before the next fix refetches it. WeatherKit's current conditions
    /// change over minutes, not seconds, and every request counts against the app's quota.
    static let refreshInterval: TimeInterval = 10 * 60
    /// How long after a failed request the next fix tries again: soon, since a rider passing
    /// through a gap in coverage comes out the other side.
    static let retryInterval: TimeInterval = 60
    /// How old a forecast can be and still be shown while requests keep failing. Past this, W10
    /// reads "—" rather than a wind that may have turned.
    static let maxAge: TimeInterval = 30 * 60

    private enum CancelID { case fetch }

    @ObservableState
    struct State: Equatable {
        /// The latest answer, kept through failed refreshes until it is `maxAge` old.
        var forecast: AttributedForecast?
        /// When WeatherKit was last asked, whether or not it answered.
        var lastAttemptAt: Date?
        var didLastAttemptFail = false
        var isFetching = false
        /// The rider's direction of travel, degrees from true north: the last one GPS gave while
        /// moving fast enough for it to mean something (`NavigationFeature.courseSpeedFloorMPS`).
        /// Held through a stop, so W10's arrow doesn't swing at a light. Nil until the first.
        var course: Double?

        /// W10's sheet shows the next few hours: enough to see what the ride is heading into.
        static let forecastWindow: TimeInterval = 3 * 3600

        var reading: WeatherReading? { forecast?.current }
        /// Rain within `RainOutlook.window`, which W10 shows in place of the wind.
        var rain: RainOutlook? { forecast.flatMap(RainOutlook.init) }
        var forecastHours: [WeatherReading] { forecast?.hours(within: Self.forecastWindow) ?? [] }

        /// Two-sided, as `SunsetFix.isFresh` is, so a clock set back doesn't hold off the next
        /// request until it catches up.
        ///
        /// A request still out after `refreshInterval` has stalled, WeatherKit never having
        /// answered, and the next fix replaces it: otherwise W10 would read "—" for the rest of
        /// the ride.
        func isFetchDue(at now: Date) -> Bool {
            guard let lastAttemptAt else { return !isFetching }
            let interval = didLastAttemptFail && !isFetching
                ? RideWeatherFeature.retryInterval
                : RideWeatherFeature.refreshInterval
            return abs(now.timeIntervalSince(lastAttemptAt)) >= interval
        }
    }

    enum Action: Equatable {
        case locationUpdated(LocationUpdate)
        case forecastLoaded(AttributedForecast)
        case fetchFailed
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .locationUpdated(let update):
                // Held through a fix without one (`LocationUpdate.course`): a stop, or no course.
                if let course = update.course {
                    state.course = course
                }
                let now = date.now
                if let forecast = state.forecast, abs(now.timeIntervalSince(forecast.fetchedAt)) >= Self.maxAge {
                    state.forecast = nil
                }
                guard state.isFetchDue(at: now) else { return .none }
                state.isFetching = true
                state.lastAttemptAt = now
                let coordinate = RouteCoordinate(
                    latitude: update.coordinate.latitude,
                    longitude: update.coordinate.longitude
                )
                return .run { send in
                    do {
                        let forecast = try await weatherClient.attributedForecast(coordinate, date: date)
                        await send(.forecastLoaded(forecast))
                    } catch {
                        // Logged in WeatherClient. A stalled request the next one replaced is
                        // cancelled, and a cancelled effect's send goes nowhere.
                        await send(.fetchFailed)
                    }
                }
                .cancellable(id: CancelID.fetch, cancelInFlight: true)

            case .forecastLoaded(let forecast):
                state.forecast = forecast
                state.isFetching = false
                state.didLastAttemptFail = false
                return .none

            case .fetchFailed:
                // The last forecast stays until it is `maxAge` old.
                state.isFetching = false
                state.didLastAttemptFail = true
                return .none
            }
        }
    }
}
