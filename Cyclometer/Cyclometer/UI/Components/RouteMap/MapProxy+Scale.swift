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
        // Wide enough that the probe, half the width from the centre at most, lands on the map.
        guard mapSize.width >= 2 * Self.scaleProbePoints else { return nil }
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

extension View {
    /// Keeps `metersPerPoint` measured from the map `proxy` reads: when the map is laid out, and on
    /// every camera frame, so the direction arrows hold their size through a pinch (#341). Applied
    /// to the `Map` itself, on S19, S20 and the live map.
    ///
    /// Written only when the snapped scale changes by a step (`quantizedScale`), so panning and
    /// following redraw nothing and a pinch redraws only as often as the arrows' size visibly
    /// changes. A failed measurement keeps the last good scale: arrows a frame stale beat arrows
    /// that blink out. While `isEnabled` is false nothing is measured — the live map with no route
    /// to draw arrows on.
    func measuresMapScale(_ proxy: MapProxy, into metersPerPoint: Binding<Double?>,
                          isEnabled: Bool = true) -> some View {
        modifier(MapScaleMeasurement(proxy: proxy, metersPerPoint: metersPerPoint, isEnabled: isEnabled))
    }
}

private struct MapScaleMeasurement: ViewModifier {
    let proxy: MapProxy
    @Binding var metersPerPoint: Double?
    let isEnabled: Bool
    /// The map's size on screen: its centre is where the scale is measured.
    @State private var mapSize = CGSize.zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                mapSize = size
                measure()
            }
            .onMapCameraChange(frequency: .continuous) { _ in measure() }
            .onMapCameraChange(frequency: .onEnd) { _ in measure() }
            .onChange(of: isEnabled) { measure() }
    }

    private func measure() {
        guard isEnabled, let measured = proxy.metersPerPoint(mapSize: mapSize),
              measured != metersPerPoint
        else { return }
        metersPerPoint = measured
    }
}
