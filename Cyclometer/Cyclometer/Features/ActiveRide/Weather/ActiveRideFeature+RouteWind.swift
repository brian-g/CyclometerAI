import ComposableArchitecture
import Foundation

/// W10's wind map along the route being ridden (#561).
///
/// Here rather than in `RideWeatherFeature` because the timing needs the ride: the route and how far
/// along it the rider is (`NavigationFeature`), where they are, and how fast they have been riding.
extension ActiveRideFeature {
    /// How far a ride goes before its own average moving speed times the route ahead. Before it,
    /// a stop at the first light would put the rider hours behind; S05.1's estimate stands in.
    static let routeWindOwnSpeedMeters = 5_000.0

    private enum RouteWindCancelID { case estimate }

    /// The sheet's opening samples the route ahead, unless a sampling began within
    /// `RideWeatherFeature.refreshInterval`. Nothing to do on a free ride, before the first fix,
    /// or with no forecast to be the first sample.
    func openWeatherSheet(_ state: inout State) -> Effect<Action> {
        let now = date.now
        guard state.navigation.activeRoute != nil, state.coordinate != nil,
              state.weather.forecast(at: now) != nil,
              !state.weather.routeWind.isFresh(at: now)
        else { return .none }
        if state.distanceMeters >= Self.routeWindOwnSpeedMeters, state.averageSpeedMPS > 0 {
            return loadRouteWind(&state, speedMPS: state.averageSpeedMPS)
        }
        guard let routeID = state.route?.id else {
            return loadRouteWind(&state, estimate: nil)
        }
        return .run { send in
            // A failed read is no estimate: the route is timed by the default ride window.
            await send(.routeWindEstimated(try? await persistenceClient.rideEstimate(forRoute: routeID)))
        }
        .cancellable(id: RouteWindCancelID.estimate, cancelInFlight: true)
    }

    /// Before `routeWindOwnSpeedMeters`: the route ridden in its estimate, as S05.1 and S20 assume.
    func loadRouteWind(_ state: inout State, estimate: TimeInterval?) -> Effect<Action> {
        guard let route = state.navigation.activeRoute else { return .none }
        return loadRouteWind(
            &state,
            speedMPS: WindSampling.speedMPS(routeDistanceMeters: route.totalDistanceMeters, estimate: estimate)
        )
    }

    /// Samples the route from where the rider is to the finish, each point timed at `speedMPS` from
    /// now. W10's own reading, where the rider is, is the first sample, so only the points ahead
    /// cost requests.
    private func loadRouteWind(_ state: inout State, speedMPS: Double) -> Effect<Action> {
        let now = date.now
        guard let route = state.navigation.activeRoute, let coordinate = state.coordinate,
              let forecast = state.weather.forecast(at: now)
        else { return .none }
        let points = WindSampling.points(
            coordinates: route.coordinates,
            cumulative: route.cumulativeDistances,
            fromMeters: state.navigation.progressMeters ?? 0,
            isLoop: route.isLoop,
            start: now,
            speedMPS: speedMPS
        )
        let rider = RouteCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude, elevationMeters: nil)
        let known = WindSample(coordinate: rider, reading: forecast.current)
        return .send(.weather(.routeWind(.load(known: known, ahead: Array(points.dropFirst())))))
    }
}
