import Foundation

/// How long a ride on a route will take, worked out before it starts (#149), so the Start sheet's
/// forecast covers the hours the rider will be out.
///
/// From the rider's own riding, in order of how much it says about this route:
/// 1. Their earlier rides of it: the route's distance at the **median speed** of those rides.
///    Speed rather than time, so a ride abandoned halfway still counts for what it rode, and for
///    complete rides it comes to the median time.
/// 2. Their recent riding anywhere: the route's distance at the overall speed of their last
///    `recentRideCount` rides.
/// 3. Nothing to go on: `nil`, and the caller uses its default.
///
/// Speeds are over moving time (`durationSeconds` excludes pauses), so the estimate leaves out
/// stops.
enum RideDurationEstimate {
    /// Enough rides to smooth one unusual day, few enough to follow a rider's season.
    static let recentRideCount = 10

    static func seconds(
        routeDistanceMeters: Double,
        routeRides: [RouteRideSummary],
        recentRides: [RideListSummary]
    ) -> TimeInterval? {
        guard routeDistanceMeters > 0 else { return nil }

        let routeSpeeds = routeRides
            .filter { $0.distanceMeters > 0 && $0.durationSeconds > 0 }
            .map { $0.distanceMeters / $0.durationSeconds }
        if let speed = median(routeSpeeds) {
            return routeDistanceMeters / speed
        }

        // Newest first, as `fetchRides` returns them.
        let recent = recentRides
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
