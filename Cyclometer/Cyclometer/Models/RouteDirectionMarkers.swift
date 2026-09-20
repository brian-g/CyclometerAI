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

    /// Roughly this many arrows across the viewport, whatever it is showing. This is what
    /// makes the spacing zoom-adaptive: it is a fraction of what is on screen, not of the
    /// route, so a 5 km route and a 100 km route read the same at the zoom you view them at.
    ///
    /// Halved from 8 after review: the arrows annotate a line the rider can already see, and
    /// at that density they were reading as the line rather than as its direction.
    static let arrowsAcrossViewport = 4.0

    /// Ground distance between arrows for a given viewport.
    static func spacingMeters(for visibleBounds: RouteBounds) -> Double {
        // The viewport's east-west extent, measured on the tangent plane at its own middle
        // latitude — the same primitive every other distance in this app is built on, so the
        // spacing cannot disagree with the route lengths it is drawn against.
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
        return quantized(abs(width) / arrowsAcrossViewport)
    }

    /// The spacing rounded up to the next multiple-of-two rung above `baseSpacingMeters`.
    ///
    /// **This is what keeps the arrows still while the rider zooms.** Spacing derived straight
    /// from the viewport is a continuous function of it, so every pinch moved every arrow to a
    /// new place on the road. On the ladder, arrows at a coarse zoom are a strict subset of the
    /// arrows at a fine one: zooming in only puts new arrows *between* the ones already there,
    /// and zooming out only takes some away.
    static func quantized(_ desiredSpacingMeters: Double) -> Double {
        guard desiredSpacingMeters.isFinite, desiredSpacingMeters > baseSpacingMeters else {
            return baseSpacingMeters
        }
        let rungs = (log2(desiredSpacingMeters / baseSpacingMeters)).rounded(.up)
        return baseSpacingMeters * pow(2, rungs)
    }

    /// Ground distance between arrows on a map that reports a camera rather than a region
    /// (#258, the live ride map). That map is pitched, and a pitched camera's region is the box
    /// around the whole frustum — it runs to the horizon, so it says nothing about how wide the
    /// road on screen reads. `MapCamera.distance` does, and it is immune to the tilt.
    ///
    /// Same constants as `spacingMeters(for:)`, so the same route reads at the same density
    /// whether the rider is browsing it on S19 or riding it.
    static func spacingMeters(forCameraDistanceMeters distance: Double) -> Double {
        guard distance.isFinite, distance > 0 else { return baseSpacingMeters }
        return quantized(distance / arrowsAcrossViewport)
    }

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

    /// The on-screen angle an arrow must be drawn at to point along `bearingDegrees`, on a map
    /// turned to `headingDegrees` and tilted to `pitchDegrees` (#258).
    ///
    /// `Annotation` content is screen-space: MapKit neither turns it with the map nor lays it in
    /// the map plane. S19 and S20 dodge this by refusing rotation and pitch (`RoutesView`), but
    /// the live map is heading-up and tilted by design, so the angle is computed instead.
    ///
    /// Two corrections, in order: the map's heading turns the world under the glyph, and the tilt
    /// foreshortens the screen's vertical axis by `cos(pitch)` while leaving the horizontal one
    /// alone. A due-north bearing on a heading-up map pointing north is screen-up either way; a
    /// bearing at 45° to the camera is drawn nearer the horizontal the more the map is tilted.
    static func screenAngleDegrees(
        bearingDegrees: Double,
        headingDegrees: Double,
        pitchDegrees: Double
    ) -> Double {
        guard bearingDegrees.isFinite, headingDegrees.isFinite else { return 0 }
        let relative = (bearingDegrees - headingDegrees) * .pi / 180
        // A pitch MapKit has not reported yet, or one outside the range it can draw, is treated
        // as flat rather than allowed to flip or collapse the glyph.
        let pitch = pitchDegrees.isFinite ? min(max(pitchDegrees, 0), 89) * .pi / 180 : 0
        let angle = atan2(sin(relative), cos(relative) * cos(pitch)) * 180 / .pi
        return angle < 0 ? angle + 360 : angle
    }

    /// Arrow placements along `coordinates`, spaced for `visibleBounds` and culled to it.
    ///
    /// Nil bounds means no arrows: the caller has no camera yet, and guessing a spacing from
    /// the route's own length would make the same route read differently on two screens.
    static func placements(
        coordinates: [RouteCoordinate],
        visibleBounds: RouteBounds?,
        limit: Int = 12
    ) -> [Placement] {
        guard let visibleBounds else { return [] }
        return placements(
            coordinates: coordinates,
            spacingMeters: spacingMeters(for: visibleBounds),
            visibleBounds: visibleBounds,
            limit: limit
        )
    }

    /// The same, for a caller that derives its spacing some other way — the live map, from its
    /// camera distance rather than from a region it cannot trust (see
    /// `spacingMeters(forCameraDistanceMeters:)`). `visibleBounds` still culls: off-screen
    /// arrows cost annotations for nothing.
    ///
    /// Positions are distances *along the route*, not source points, so the result does not
    /// depend on how the GPX happened to be sampled (#192) — a file with a point every 200 m and
    /// one with a point every metre describe the same road and get the same arrows.
    static func placements(
        coordinates: [RouteCoordinate],
        spacingMeters spacing: Double,
        visibleBounds: RouteBounds,
        limit: Int = 12
    ) -> [Placement] {
        guard coordinates.count > 1, limit > 0, spacing.isFinite, spacing > 0 else { return [] }

        let cumulative = RouteGeometry.cumulativeDistances(coordinates)
        guard let total = cumulative.last, total > 0 else { return [] }

        // Distances along the route to put an arrow at. Multiples of the spacing, so a coarser
        // spacing is a subset of a finer one and zooming never moves an arrow that stays.
        var distances = stride(from: spacing, to: total, by: spacing).map { $0 }
        if distances.isEmpty {
            // The whole route is shorter than one spacing. It still has a direction, and one
            // arrow in the middle of it is what says so.
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
        return thinned(placements, to: limit)
    }

    /// At most `limit` placements, spread across the whole line rather than taken from its
    /// start.
    ///
    /// Spacing is measured *along the route*, not across the screen, so a switchback climb or a
    /// criterium loop that doubles back inside one viewport produces far more in-view samples
    /// than the cap allows. Truncating would leave the back half of a visible line with no
    /// arrows at all, which reads as "this part has no direction" rather than as a cap.
    private static func thinned(_ placements: [Placement], to limit: Int) -> [Placement] {
        guard placements.count > limit else { return placements }
        // `limit - 1` is the denominator below, so one arrow is its own case — the middle of
        // the line, not the start of it.
        guard limit > 1 else { return [placements[placements.count / 2]] }
        // Evenly spaced indices across the whole array, endpoints included.
        return (0..<limit).map { step in
            placements[Int((Double(step) * Double(placements.count - 1) / Double(limit - 1)).rounded())]
        }
    }
}
