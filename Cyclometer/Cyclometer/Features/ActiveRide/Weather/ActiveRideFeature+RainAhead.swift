import ComposableArchitecture
import Foundation

/// Rain along the route being ridden (#152): a silent banner when the route ahead is wet.
///
/// Here rather than in `RideWeatherFeature`, for the same reason as the wind map: the timing needs
/// the ride's route, where the rider is along it, and how fast they have been riding. The banner is
/// informational and goes nowhere near `AlertOrchestratorFeature`: no tone, no haptic, and no
/// alert level, which means a vehicle.
extension ActiveRideFeature {
    private enum RainAheadCancelID { case estimate }

    /// Checks the route the rider reaches within `RainOutlook.window`, on each fresh forecast where
    /// the rider is: about every `RideWeatherFeature.refreshInterval`. Nothing to do on a free ride
    /// or before the first fix.
    func checkRainAhead(_ state: inout State) -> Effect<Action> {
        let now = date.now
        guard let route = state.navigation.activeRoute, let coordinate = state.coordinate,
              state.weather.forecast(at: now) != nil
        else { return .none }
        let rider = RouteCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude, elevationMeters: nil)
        let progress = Self.routeAheadProgressMeters(
            of: rider, on: route, navigation: state.navigation, course: state.weather.course
        )
        if let speedMPS = Self.ownSpeedMPS(state) {
            return Self.rainAheadCheck(route: route, progress: progress, start: now, speedMPS: speedMPS)
                .map(Effect.send) ?? .none
        }
        let routeID = state.route?.id
        return .run { send in
            // Before the ride's own speed means anything, the route ridden in its estimate, as the
            // wind map times it. A failed read is no estimate: the default ride window.
            var estimate: TimeInterval?
            if let routeID {
                estimate = try? await persistenceClient.rideEstimate(forRoute: routeID)
            }
            let speedMPS = WindSampling.speedMPS(routeDistanceMeters: route.totalDistanceMeters, estimate: estimate)
            if let check = Self.rainAheadCheck(route: route, progress: progress, start: now, speedMPS: speedMPS) {
                await send(check)
            }
        }
        .cancellable(id: RainAheadCancelID.estimate, cancelInFlight: true)
    }

    /// The stretch from `progress` to as far as `speedMPS` gets in `RainOutlook.window`, sampled as
    /// the wind map samples. Its first point is where the rider is, which W10's own forecast
    /// answers, so only the points ahead cost requests.
    static func rainAheadCheck(
        route: NavigationRoute, progress: Double, start: Date, speedMPS: Double
    ) -> Action? {
        let points = WindSampling.points(
            coordinates: route.coordinates,
            cumulative: route.cumulativeDistances,
            fromMeters: progress,
            toMeters: progress + speedMPS * RainOutlook.window,
            isLoop: route.isLoop,
            start: start,
            speedMPS: speedMPS
        )
        guard let rider = points.first else { return nil }
        return .weather(.checkRainAhead(rider: rider, ahead: Array(points.dropFirst())))
    }
}
