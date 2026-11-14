import Foundation

/// Where the wind map asks WeatherKit about the wind, and which of its answers to draw (#561).
///
/// WeatherKit answers one point per request, with no wind field or tiles, and every request counts
/// against the app's quota. So the map samples:
/// - **Along a route** (S20, and W10's sheet mid-route): one point per `spacingMeters` of the
///   distance left, `minimumSamples` to `maximumSamples` of them. Each point's wind is the forecast
///   for the hour the rider is expected there, not the wind there now. The first point is where
///   the screen's own forecast was fetched, so it costs nothing.
/// - **With no route** (W10's sheet): no requests at all. WeatherKit's wind barely changes across
///   the few kilometres the sheet's map shows, so W10's one reading is drawn as an even field
///   (`field(in:)`).
///
/// Pure arithmetic, so it is tested without a map or the network.
enum WindSampling {
    /// One sample per this much route. Brian's call (#561): WeatherKit's wind changes over tens of
    /// kilometres, not hundreds of metres.
    static let spacingMeters = 10_000.0
    /// The start and the finish, or the start and halfway round a loop.
    static let minimumSamples = 2
    /// The most requests one look at the map spends, however long the route.
    static let maximumSamples = 8
    /// How far past a whole number of `spacingMeters` the distance left must run to earn another
    /// sample. A route measured at 20 000.0001 m is 20 km, not a reason for a third request.
    static let spacingToleranceMeters = 1.0

    // MARK: - Along a route

    /// The distances along a route of `totalMeters` to sample, from `fromMeters` to the finish,
    /// evenly spaced.
    ///
    /// A loop sampled from its start ends where it began, so its finish would ask about the start
    /// again: it is left out, and two samples on a loop are the start and halfway. From anywhere
    /// else on a loop the finish is still ahead, so it counts.
    static func distances(totalMeters: Double, fromMeters: Double = 0, isLoop: Bool = false) -> [Double] {
        guard totalMeters.isFinite, totalMeters > 0 else { return [0] }
        let start = min(max(fromMeters.isFinite ? fromMeters : 0, 0), totalMeters)
        let remaining = totalMeters - start
        guard remaining > 0 else { return [start] }
        let intervals = Int(((remaining - spacingToleranceMeters) / spacingMeters).rounded(.up))
        if isLoop && start == 0 {
            let count = clamped(intervals)
            return (0..<count).map { start + remaining * Double($0) / Double(count) }
        }
        let count = clamped(intervals + 1)
        return (0..<count).map { start + remaining * Double($0) / Double(count - 1) }
    }

    /// `distances` as places on the route, each timed for a rider leaving `fromMeters` at `start`
    /// and riding at `speedMPS`. The first is where the rider is (or the route's start).
    static func points(
        coordinates: [RouteCoordinate],
        cumulative: [Double],
        fromMeters: Double = 0,
        isLoop: Bool = false,
        start: Date,
        speedMPS: Double
    ) -> [WindSamplePoint] {
        guard let total = cumulative.last else { return [] }
        let origin = min(max(fromMeters, 0), total)
        return distances(totalMeters: total, fromMeters: origin, isLoop: isLoop).compactMap { distance in
            guard let coordinate = RouteGeometry.coordinate(coordinates, atMeters: distance, cumulative: cumulative)
            else { return nil }
            let seconds = speedMPS > 0 ? (distance - origin) / speedMPS : 0
            return WindSamplePoint(coordinate: coordinate, distanceMeters: distance, arrival: start.addingTimeInterval(seconds))
        }
    }

    /// The speed a route of `routeDistanceMeters` is ridden at when it takes the forecast's ride
    /// window: the route's estimate, or `AttributedForecast.defaultRideWindow` without one (S20,
    /// and W10 before the ride's own average means anything).
    static func speedMPS(routeDistanceMeters: Double, estimate: TimeInterval?) -> Double {
        routeDistanceMeters / AttributedForecast.rideWindow(estimate: estimate)
    }

    /// The reading for `date` from one point's answer: the current conditions while the hour
    /// they were observed in is under way (observed beats forecast), else the forecast hour
    /// containing `date`. Nil past the end of the forecast.
    static func reading(at date: Date, current: WeatherReading, hourly: [WeatherReading]) -> WeatherReading? {
        func contains(_ hour: WeatherReading, _ instant: Date) -> Bool {
            hour.date <= instant && instant < hour.date.addingTimeInterval(AttributedForecast.hourLength)
        }
        guard let hour = hourly.first(where: { contains($0, date) }) else {
            // Before the forecast's first hour is now, which the current conditions describe.
            let isBeforeForecast = hourly.first.map { date < $0.date } ?? true
            return isBeforeForecast ? current : nil
        }
        return contains(hour, current.date) ? current : hour
    }

    // MARK: - With no route

    /// Columns across the no-route field; rows follow the map's shape. Even, so no arrow sits at the
    /// centre, under the rider's location dot.
    static let fieldColumns = 4

    /// The no-route field's arrow positions: the centres of an even grid over `bounds`, which is
    /// the map's visible region, so the field fills whatever the rider has zoomed to.
    static func field(in bounds: RouteBounds) -> [RouteCoordinate] {
        let latitudeSpan = bounds.maxLatitude - bounds.minLatitude
        let longitudeSpan = bounds.maxLongitude - bounds.minLongitude
        guard latitudeSpan > 0, longitudeSpan > 0 else { return [] }
        let southWest = RouteCoordinate(latitude: bounds.minLatitude, longitude: bounds.minLongitude, elevationMeters: nil)
        let northEast = RouteCoordinate(latitude: bounds.maxLatitude, longitude: bounds.maxLongitude, elevationMeters: nil)
        let extent = RouteGeometry.tangentPlaneOffset(from: southWest, to: northEast)
        let rows = max(1, Int((Double(fieldColumns) * extent.north / extent.east).rounded()))
        return (0..<rows).flatMap { row in
            (0..<fieldColumns).map { column in
                RouteCoordinate(
                    latitude: bounds.minLatitude + latitudeSpan * (Double(row) + 0.5) / Double(rows),
                    longitude: bounds.minLongitude + longitudeSpan * (Double(column) + 0.5) / Double(fieldColumns),
                    elevationMeters: nil
                )
            }
        }
    }

    private static func clamped(_ count: Int) -> Int {
        min(max(count, minimumSamples), maximumSamples)
    }
}
