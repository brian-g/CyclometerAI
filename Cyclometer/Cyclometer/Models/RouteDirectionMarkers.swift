import Foundation

/// Where the direction-of-travel arrows go on a route, and which way each one points.
///
/// Pure arithmetic over values, deliberately: a live `Map` cannot be pixel-snapshot-tested
/// reliably (tiles render asynchronously — `RoutesMapCamera.swift:6-9`), so the part of the
/// direction indicator that can be wrong is kept where ordinary tests can reach it and the
/// `MapContent` wrapper is left with nothing to decide.
///
/// UX.md §S20 asks for direction of travel on the route detail map; #194 puts the same
/// treatment on S19's map, which is why this is shared rather than living in either screen.
enum RouteDirectionMarkers {

    struct Placement: Equatable, Sendable {
        var coordinate: RouteCoordinate
        /// Degrees clockwise from true north, matching `RouteGeometry.bearingDegrees`.
        var bearingDegrees: Double
    }

    /// The finest spacing arrows are ever placed at, and the rung every coarser spacing is a
    /// multiple of. Without a floor, a viewport a few hundred metres wide would ask for an arrow
    /// every couple of metres and bury the line it is annotating.
    static let baseSpacingMeters = 100.0

    /// How far either side of an arrow the route is read to decide which way it points.
    ///
    /// Small enough to follow a corner, large enough that a wobble in the source file does not
    /// swing the arrow: a GPX sampled every metre in a suburb has metre-scale noise, and a chord
    /// over two such points can point anywhere.
    static let tangentWindowMeters = 15.0

    /// How many arrows a screen should carry at most.
    ///
    /// **The density is a count of arrows on the visible line, not a fraction of the screen.**
    /// Spacing used to be the viewport's width over four, which reads correctly only where the
    /// route crosses the screen once. A route that meanders — a 7 km loop inside a 5 km viewport —
    /// has far more line on screen than the screen is wide, and that rule gave it two arrows for
    /// the whole loop (#258 review). Counting what is actually drawn cannot make that mistake.
    static let targetArrowsInView = 12

    /// The arrow's size at the base rung of the ladder, in points.
    ///
    /// Read against a real route at a street-level zoom (#258 review): the arrow is drawn in the
    /// line's own colour, so its size is the only thing separating it from the line, and below
    /// this it reads as a thickening rather than as an arrowhead.
    static let baseArrowPoints = 20.0

    /// How much bigger the arrow gets per rung of the spacing ladder.
    static let arrowPointsPerRung = 1.0

    /// The largest an arrow is ever drawn. A world-zoom camera is a dozen rungs up, and without a
    /// ceiling the arrow would dwarf the route it annotates.
    static let maximumArrowPoints = 28.0

    /// How big to draw an arrow at `spacing` — semantic zoom (#258 review).
    ///
    /// A fixed point size cannot be right at two zooms: the map's own features shrink as the
    /// camera pulls back, so an arrow that sits well against a street reads as a speck against a
    /// county. The size therefore climbs with the ladder, one point per rung, which keeps it in
    /// proportion to what is around it.
    ///
    /// Taking the rung rather than the raw viewport width is deliberate: the size then changes at
    /// exactly the zooms the *density* changes at, so a pinch never smoothly grows the arrows.
    static func arrowPoints(forSpacingMeters spacing: Double) -> Double {
        guard spacing.isFinite, spacing > baseSpacingMeters else { return baseArrowPoints }
        let rungs = log2(spacing / baseSpacingMeters).rounded()
        return min(baseArrowPoints + rungs * arrowPointsPerRung, maximumArrowPoints)
    }

    /// How much of an arrow's point size its triangle spans, tip to base and side to side.
    ///
    /// The arrows were an SF Symbol, `arrowtriangle.up.fill`, whose ink is 16 × 16 pt at 20 pt
    /// bold. Drawing the triangle at this fraction of `arrowPoints` keeps the size #258's review
    /// settled on.
    static let arrowInkFraction = 0.8

    /// How many metres one screen point covers, given two points `pointsApart` on screen that the
    /// map reports at `start` and `end`. What turns an arrow's point size into a size on the ground.
    ///
    /// Measured from the map rather than estimated from a viewport (#341 review): a camera's
    /// distance, or the region a map was asked to show, says little about the scale it actually
    /// draws at once tilt, field of view and the map's shape are involved. Nil when there is
    /// nothing to divide: no distance on screen, or no distance on the ground.
    static func metersPerPoint(from start: RouteCoordinate, to end: RouteCoordinate,
                               pointsApart: Double) -> Double? {
        let perPoint = RouteGeometry.segmentMeters(from: start, to: end) / pointsApart
        guard pointsApart.isFinite, pointsApart > 0, perPoint.isFinite, perPoint > 0
        else { return nil }
        return perPoint
    }

    /// The smallest change in scale worth redrawing the arrows for: 2 %, which on a 22 pt arrow
    /// is under half a point.
    static let scaleStep = 0.02

    /// `metersPerPoint` snapped to a power of `1 + scaleStep`.
    ///
    /// The scale is re-measured on every camera frame so the arrows hold their size through a
    /// pinch, and each new value redraws the map's content. Snapping means it changes only when
    /// the arrow's size visibly would, so a map that pans or follows without zooming redraws
    /// nothing at all.
    static func quantizedScale(_ metersPerPoint: Double) -> Double {
        guard metersPerPoint.isFinite, metersPerPoint > 0 else { return metersPerPoint }
        let step = log(1 + scaleStep)
        return exp((log(metersPerPoint) / step).rounded() * step)
    }

    /// The triangle an arrow is drawn as: centred on `placement`, its tip `sizeMeters / 2` ahead
    /// along the bearing, its base as wide as the arrow is long (#341).
    ///
    /// On the map plane rather than on screen, which is the point. An `Annotation` draws above
    /// every overlay *and* can draw above the rider's location dot, and SwiftUI's `Map` has no way
    /// to order annotations. An overlay always draws beneath annotations. Lying in the map plane
    /// also means MapKit turns and tilts the arrow with the map, so a heading-up, tilted camera
    /// needs no correction.
    static func arrowTriangle(for placement: Placement, sizeMeters: Double) -> [RouteCoordinate] {
        let bearing = placement.bearingDegrees * .pi / 180
        let half = sizeMeters / 2
        // Unit vectors along the bearing and to its right, as (north, east).
        let ahead = (north: cos(bearing), east: sin(bearing))
        let right = (north: -sin(bearing), east: cos(bearing))
        func point(along: Double, across: Double) -> RouteCoordinate {
            RouteGeometry.coordinate(
                offsetFrom: placement.coordinate,
                north: ahead.north * along + right.north * across,
                east: ahead.east * along + right.east * across
            )
        }
        return [
            point(along: half, across: 0),
            point(along: -half, across: half),
            point(along: -half, across: -half),
        ]
    }

    /// The arrows to draw on a route, and the spacing they were drawn at.
    ///
    /// The spacing comes back because it is what sizes the arrow — see
    /// `arrowPoints(forSpacingMeters:)`. Density and size are two readings of one number, so they
    /// cannot disagree.
    struct Arrows: Equatable, Sendable {
        var placements: [Placement]
        /// The rung the climb settled at. Per route, so it says nothing about the arrow's size.
        var spacingMeters: Double
        /// How big to draw each one. Derived from the *viewport*, not from `spacingMeters`, so
        /// two routes on one screen are drawn with the same arrow even when a long one and a
        /// short one settle at different rungs (S19 draws every saved route at once).
        var pointSize: Double

        static let none = Arrows(placements: [], spacingMeters: baseSpacingMeters,
                                 pointSize: baseArrowPoints)
    }

    /// The closest two arrows may ever be drawn *on screen*, expressed as a spacing on the ground.
    ///
    /// The density rule counts arrows on the visible line, which is right until the line is barely
    /// on the screen at all: S19 opens on a viewport 160 km wide, where a 5 km route renders as a
    /// dot, and counting alone would happily stack a dozen arrows on that dot. A floor of the
    /// viewport's width over `targetArrowsInView` says that whatever else happens, two arrows are
    /// never closer together than a twelfth of the screen.
    ///
    /// Snapped up to a rung of the ladder, because the climb starts here and every rung above it
    /// must stay a multiple of the base for the nesting to hold.
    static func spacingFloor(for visibleBounds: RouteBounds) -> Double {
        // The viewport's east-west extent, measured on the tangent plane at its own middle
        // latitude — the same primitive every other distance in this app is built on, so the
        // floor cannot disagree with the route lengths it is drawn against.
        let centerLatitude = visibleBounds.center.latitude
        let width = RouteGeometry.tangentPlaneOffset(
            from: RouteCoordinate(latitude: centerLatitude,
                                  longitude: visibleBounds.minLongitude,
                                  elevationMeters: nil),
            to: RouteCoordinate(latitude: centerLatitude,
                                longitude: visibleBounds.maxLongitude,
                                elevationMeters: nil)
        ).east
        guard width.isFinite else { return baseSpacingMeters }
        let wanted = abs(width) / Double(targetArrowsInView)
        guard wanted > baseSpacingMeters else { return baseSpacingMeters }
        return baseSpacingMeters * pow(2, log2(wanted / baseSpacingMeters).rounded(.up))
    }

    /// Arrows along `coordinates`, as many as `limit` allows, for the viewport `visibleBounds`.
    ///
    /// The spacing is found rather than given: start at the floor the viewport sets and climb the
    /// ladder until no more than `limit` arrows are on screen. What sets the density is therefore
    /// how much *line* is in view — the same viewport reading a straight road and a loop that
    /// doubles through it four times should not get the same number of arrows — while the floor
    /// keeps arrows from stacking on a route that is only a dot on the screen.
    ///
    /// `drawingBounds` is where arrows are actually placed, and defaults to the viewport. The live
    /// map passes something wider: it only re-places when the rider leaves the viewport, so arrows
    /// have to already exist beyond it or the rider rides into an empty road (#258 review).
    ///
    /// Nil bounds means no arrows: the caller has no camera yet, and there is nothing to count
    /// arrows against.
    static func arrows(
        coordinates: [RouteCoordinate],
        visibleBounds: RouteBounds?,
        drawingBounds: RouteBounds? = nil,
        limit: Int = targetArrowsInView
    ) -> Arrows {
        guard let visibleBounds else { return .none }
        let floor = spacingFloor(for: visibleBounds)
        return arrows(
            coordinates: coordinates,
            spacingMeters: floor,
            visibleBounds: visibleBounds,
            drawingBounds: drawingBounds,
            pointSize: arrowPoints(forSpacingMeters: floor),
            limit: limit
        )
    }

    /// The same, starting the climb at `spacingMeters` rather than at the finest rung — what a
    /// test uses to pin one rung, and what a caller with a reason to start coarse would use.
    /// `visibleBounds` culls: off-screen arrows cost overlays for nothing.
    ///
    /// **Too many in view is answered by climbing the ladder, not by dropping arrows.** A route
    /// that doubles back inside one viewport — a criterium lap, a switchback climb — can put far
    /// more than `limit` arrows on screen. Thinning that list to `limit` evenly spaced *entries*
    /// (what this did first) keeps every arrow on the lattice but picks a different subset of it
    /// at each zoom, so arrows appear to move about as the rider pinches. Doubling the spacing
    /// until the count fits keeps the nesting: every arrow at a coarse zoom is also an arrow at
    /// every finer one, and zooming only ever adds arrows between the ones already there.
    ///
    /// Positions are distances *along the route*, not source points, so the result does not
    /// depend on how the GPX happened to be sampled (#192) — a file with a point every 200 m and
    /// one with a point every metre describe the same road and get the same arrows.
    static func arrows(
        coordinates: [RouteCoordinate],
        spacingMeters requestedSpacing: Double,
        visibleBounds: RouteBounds,
        drawingBounds: RouteBounds? = nil,
        pointSize: Double = baseArrowPoints,
        limit: Int = targetArrowsInView
    ) -> Arrows {
        guard coordinates.count > 1, limit > 0,
              requestedSpacing.isFinite, requestedSpacing > 0
        else { return .none }

        let cumulative = RouteGeometry.cumulativeDistances(coordinates)
        guard let total = cumulative.last, total > 0 else { return .none }

        var spacing = requestedSpacing
        while true {
            // Counted against what is on screen, so a wider `drawingBounds` cannot coarsen the
            // spacing the rider sees.
            let onScreen = placements(coordinates: coordinates, spacingMeters: spacing,
                                      visibleBounds: visibleBounds, cumulative: cumulative,
                                      total: total)
            // Past the route's own length there is no coarser rung to climb to: the whole route
            // is one span, and the midpoint arrow is all there is to draw.
            if onScreen.count <= limit || spacing >= total {
                let drawn = drawingBounds.map {
                    placements(coordinates: coordinates, spacingMeters: spacing,
                               visibleBounds: $0, cumulative: cumulative, total: total)
                } ?? onScreen
                return Arrows(placements: drawn, spacingMeters: spacing, pointSize: pointSize)
            }
            spacing *= 2
        }
    }

    /// One pass at one spacing: an arrow at every multiple of it that is on screen.
    private static func placements(
        coordinates: [RouteCoordinate],
        spacingMeters spacing: Double,
        visibleBounds: RouteBounds,
        cumulative: [Double],
        total: Double
    ) -> [Placement] {
        // Multiples of the spacing, so a coarser spacing is a subset of a finer one and zooming
        // never moves an arrow that stays.
        var distances = Array(stride(from: spacing, to: total, by: spacing))
        if distances.isEmpty {
            // The whole route is shorter than one spacing. It still has a direction, and one
            // arrow in the middle of it is what says so. The only arrow not on the lattice, and
            // the only one that can move under a zoom — it is also the only one there is.
            distances = [total / 2]
        }

        var placements: [Placement] = []
        for distance in distances {
            guard let coordinate = RouteGeometry.coordinate(coordinates, atMeters: distance,
                                                            cumulative: cumulative),
                  visibleBounds.contains(latitude: coordinate.latitude,
                                         longitude: coordinate.longitude)
            else { continue }
            // The direction of the line *here*, not the chord back to the previous arrow: at a
            // browsing zoom those are hundreds of metres apart, and on a curving road the chord
            // runs at an angle to the stretch of line the arrow is drawn on.
            guard let bearing = RouteGeometry.tangentBearingDegrees(
                coordinates,
                atMeters: distance,
                windowMeters: min(tangentWindowMeters, spacing / 2),
                cumulative: cumulative
            ) else { continue }
            placements.append(Placement(coordinate: coordinate, bearingDegrees: bearing))
        }
        return placements
    }
}
