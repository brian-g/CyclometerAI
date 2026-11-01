import MapKit
import SwiftUI

/// The direction-of-travel arrows for a route, drawn where `RouteDirectionMarkers` put them.
///
/// Its own `MapContent` because three maps draw them and none of them should own a copy of the
/// shape: S19 and S20 through `RouteMapContent`, and the live ride map directly (#258).
///
/// A filled triangle rather than a chevron (#258 review). A chevron is an open V — on a line its
/// own colour it reads as a kink in the line rather than as an arrowhead, which is exactly what
/// it looked like on S20.
///
/// A `MapPolygon` on the map plane, not an `Annotation` (#341). Annotations can draw above the
/// rider's location dot, and SwiftUI's `Map` has no way to order them; overlays always draw
/// beneath annotations, so the dot stays on top. Lying in the map plane, the arrow also turns and
/// tilts with a heading-up, tilted camera without any correction. The geometry is in
/// `RouteDirectionMarkers.arrowTriangle(for:sizeMeters:)`, where tests can reach it.
struct RouteDirectionArrows: MapContent {
    let placements: [RouteDirectionMarkers.Placement]
    /// How big to draw each arrow, in screen points. From
    /// `RouteDirectionMarkers.arrowPoints(forSpacingMeters:)`, so the arrow keeps its proportion
    /// to the map as the camera pulls back (#258 review).
    let pointSize: Double
    /// What one of those points covers on the ground, from
    /// `MapProxy.metersPerPoint(mapSize:)`, measured from the map on every camera frame.
    let metersPerPoint: Double
    var tint: Color = .cyPrimary

    /// None when zoomed out past `RouteDirectionMarkers.maximumArrowMetersPerPoint`. Checked here,
    /// against the scale measured every frame, so arrows go as soon as a pinch passes it.
    @MapContentBuilder
    var body: some MapContent {
        if RouteDirectionMarkers.drawsArrows(atMetersPerPoint: metersPerPoint) {
            ForEach(Array(placements.enumerated()), id: \.offset) { _, placement in
                MapPolygon(coordinates: RouteDirectionMarkers.arrowTriangle(
                    for: placement,
                    sizeMeters: pointSize * RouteDirectionMarkers.arrowInkFraction * metersPerPoint
                ).map(\.coordinate2D))
                .foregroundStyle(tint)
            }
        }
    }
}
