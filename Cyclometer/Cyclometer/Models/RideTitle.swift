import Foundation

/// S10's default ride name (#249), for a ride the rider hasn't named: the route it followed, or
/// else when it was ridden and what shape it took — "Morning Loop", "Evening Out and Back",
/// "Afternoon Ride".
///
/// Offline and deterministic by design. A place name ("Fargo Morning Loop") needs a reverse
/// geocode, a network call, and is left to a follow-up.
enum RideTitle {

    enum Shape: Equatable {
        case loop, outAndBack, oneWay
    }

    /// How close the finish must come to the start for the ride to have come back. Far looser
    /// than `RouteMapContent.loopClosureMeters`, which judges a planned polyline: a recorded ride
    /// ends wherever the rider stopped the clock, often a driveway or a car park away.
    static let returnedToStartMeters = 250.0

    /// Spacing the track is resampled at before its halves are compared, so the comparison
    /// depends on distance ridden rather than on how many seconds each stretch took.
    static let retraceSampleMeters = 50.0

    /// How near the outbound track a point on the way back must be to count as retracing it —
    /// the far side of a road plus GPS error.
    static let retraceToleranceMeters = 75.0

    /// How far either side of its mirrored position a point on the way back looks for the way out,
    /// as a share of the ride. A point `d` from the finish retraces the point `d` from the start,
    /// give or take the few percent GPS adds to one direction's distance. Kept narrow so repeated
    /// laps — whose second half runs over their first, but not in mirror order — stay a loop.
    static let mirrorWindowShare = 0.05

    /// Share of the way back that must retrace the way out for an out-and-back. Below one, so a
    /// short detour on the return doesn't make it a loop.
    static let retraceShare = 0.8

    static func defaultTitle(
        routeName: String?,
        startedAt: Date,
        segments: [[RouteCoordinate]],
        calendar: Calendar
    ) -> String {
        if let routeName, !routeName.isEmpty { return routeName }
        let partOfDay = partOfDay(startedAt, calendar: calendar)
        switch shape(segments.flatMap { $0 }) {
        case .loop:       return "\(partOfDay) Loop"
        case .outAndBack: return "\(partOfDay) Out and Back"
        case .oneWay:     return "\(partOfDay) Ride"
        }
    }

    static func partOfDay(_ date: Date, calendar: Calendar) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12:  return "Morning"
        case 12..<17: return "Afternoon"
        case 17..<21: return "Evening"
        default:      return "Night"
        }
    }

    /// A ride that went somewhere and ended where it started is a loop, unless most of its way back
    /// runs over its way out. One that never got farther than `returnedToStartMeters` from the
    /// start has no shape — ending near the start proves nothing then. The segments are joined: a
    /// pause splits the track, not the route.
    static func shape(_ track: [RouteCoordinate]) -> Shape {
        guard let start = track.first, let finish = track.last,
              RouteGeometry.segmentMeters(from: start, to: finish) <= returnedToStartMeters,
              track.contains(where: { RouteGeometry.segmentMeters(from: start, to: $0) > returnedToStartMeters })
        else { return .oneWay }
        let samples = RouteGeometry.resampled(track, everyMeters: retraceSampleMeters).map(\.coordinate)
        let last = samples.count - 1
        let window = Int((Double(samples.count) * mirrorWindowShare).rounded(.up))
        let inbound = (samples.count / 2)...last
        let retraced = inbound.filter { index in
            let mirror = last - index
            return (max(0, mirror - window)...min(last, mirror + window)).contains {
                RouteGeometry.segmentMeters(from: samples[index], to: samples[$0]) <= retraceToleranceMeters
            }
        }
        return Double(retraced.count) / Double(inbound.count) >= retraceShare ? .outAndBack : .loop
    }
}
