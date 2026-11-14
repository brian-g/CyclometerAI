import Foundation

/// How long a ride on a route will take, worked out before it starts (#149), so the Start sheet's
/// forecast covers the hours the rider will be out.
///
/// From the rider's own riding, in order of how much it says about this route:
/// 1. `fromRouteRides`: their earlier rides of it, the route's distance at the **median speed** of
///    those rides. Speed rather than time, so a ride abandoned partway still counts for what it rode,
///    and for complete rides it comes to the median time. A ride covering less than
///    `minimumRouteShare` of the route is left out: a mistaken start says nothing about the route.
/// 2. `fromRecentRides`: their recent riding anywhere, the route's distance at the overall speed of
///    their last `recentRideCount` rides. The caller reads these only when 1 has no answer.
/// 3. Neither: `nil`, and the caller uses its default.
///
/// Speeds are over moving time (`durationSeconds` excludes pauses), so the estimate leaves out
/// stops.
enum RideDurationEstimate {
    /// Enough rides to smooth one unusual day, few enough to follow a rider's season.
    static let recentRideCount = 10
    /// The least of the route a ride must cover to count toward its estimate (Brian, #149 review).
    static let minimumRouteShare = 0.25

    /// The route's distance at the median speed of the rider's rides of it; `nil` with none that count.
    static func fromRouteRides(routeDistanceMeters: Double, rides: [RouteRideSummary]) -> TimeInterval? {
        guard routeDistanceMeters > 0 else { return nil }
        let speeds = rides
            .filter { $0.distanceMeters >= routeDistanceMeters * minimumRouteShare && $0.durationSeconds > 0 }
            .map { $0.distanceMeters / $0.durationSeconds }
        return median(speeds).map { routeDistanceMeters / $0 }
    }

    /// The route's distance at the overall speed of the rider's last `recentRideCount` rides, which
    /// `fetchRides` returns newest first; `nil` with none.
    static func fromRecentRides(routeDistanceMeters: Double, rides: [RideListSummary]) -> TimeInterval? {
        guard routeDistanceMeters > 0 else { return nil }
        let recent = rides
            .filter { $0.distanceMeters > 0 && $0.durationSeconds > 0 }
            .prefix(recentRideCount)
        guard !recent.isEmpty else { return nil }
        let speed = recent.map(\.distanceMeters).reduce(0, +) / recent.map(\.durationSeconds).reduce(0, +)
        return routeDistanceMeters / speed
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

extension PersistenceClient {
    /// How long a ride on route `id` will take, read from the rider's history in
    /// `RideDurationEstimate`'s order: the route's own rides, then their recent riding, then nil
    /// for the caller's default. S05.1 sizes its forecast by it (#149), and W10's wind map times the
    /// route ahead by it until the ride's own average means something (#561).
    ///
    /// The rider's whole ride history is read only when the route's own rides can't answer.
    func rideEstimate(forRoute id: UUID) async throws -> TimeInterval? {
        guard let summary = try await fetchRouteSummary(id) else { return nil }
        let distance = summary.distanceMeters
        if let estimate = RideDurationEstimate.fromRouteRides(
            routeDistanceMeters: distance, rides: try await fetchRouteRides(id)
        ) {
            return estimate
        }
        return RideDurationEstimate.fromRecentRides(routeDistanceMeters: distance, rides: try await fetchRides())
    }
}
