import Foundation

/// The wind at one place on the wind map (#561): where, and the reading that holds there when the
/// rider is expected to arrive.
struct WindSample: Equatable, Sendable {
    var coordinate: RouteCoordinate
    var reading: WeatherReading
    /// How far along the route the sample is (`WindSamplePoint.distanceMeters`), which S20's wind
    /// shares time each stretch of route by (#570). Nil for W10's own reading, where the rider is:
    /// the sample it hands `RouteWindFeature` along a route, and its field with none.
    var distanceMeters: Double? = nil
}

/// A place along a route to ask WeatherKit about, and when the rider is expected to reach it.
struct WindSamplePoint: Equatable, Sendable {
    var coordinate: RouteCoordinate
    /// How far along the route the point is.
    var distanceMeters: Double
    var arrival: Date
}
