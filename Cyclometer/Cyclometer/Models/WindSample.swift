import Foundation

/// The wind at one place on the wind map (#561): where, and the reading that holds there when the
/// rider is expected to arrive.
struct WindSample: Equatable, Sendable {
    var coordinate: RouteCoordinate
    var reading: WeatherReading
}

/// A place along a route to ask WeatherKit about, and when the rider is expected to reach it.
struct WindSamplePoint: Equatable, Sendable {
    var coordinate: RouteCoordinate
    /// How far along the route the point is.
    var distanceMeters: Double
    var arrival: Date
}
