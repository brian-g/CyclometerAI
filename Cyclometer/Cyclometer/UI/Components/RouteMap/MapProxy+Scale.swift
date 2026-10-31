import MapKit
import SwiftUI

extension MapProxy {
    /// How far apart, on screen, the two points the scale is measured between are.
    ///
    /// Far enough that coordinate rounding is noise against it, near enough to stay within the
    /// centre's own scale on a tilted map, where the scale changes from the bottom of the screen
    /// to the top.
    static let scaleProbePoints = 50.0

    /// What one screen point covers on the ground at the centre of a map `mapSize` big, snapped
    /// to `RouteDirectionMarkers.scaleStep` (#341 review).
    ///
    /// Measured, not estimated: MapKit converts two points across the centre, so its own tilt,
    /// field of view, aspect and projection are all in the answer. Horizontal because a tilted
    /// map foreshortens only the vertical. The centre because that is where a following map keeps
    /// the rider. Nil before the map can convert, or before it has a size.
    func metersPerPoint(mapSize: CGSize) -> Double? {
        guard mapSize.width > Self.scaleProbePoints else { return nil }
        let center = CGPoint(x: mapSize.width / 2, y: mapSize.height / 2)
        let probe = CGPoint(x: center.x + Self.scaleProbePoints, y: center.y)
        guard let start = convert(center, from: .local),
              let end = convert(probe, from: .local),
              let perPoint = RouteDirectionMarkers.metersPerPoint(
                  from: RouteCoordinate(start), to: RouteCoordinate(end),
                  pointsApart: Self.scaleProbePoints
              )
        else { return nil }
        return RouteDirectionMarkers.quantizedScale(perPoint)
    }
}

private extension RouteCoordinate {
    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude, elevationMeters: nil)
    }
}
