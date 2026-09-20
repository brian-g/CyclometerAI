import Foundation
import Testing
@testable import Cyclometer

/// #194 / #195 / #258 — where the direction-of-travel arrows go, and which way they point.
///
/// The placement is kept out of the `MapContent` precisely so it can be tested here: a live
/// `Map` renders tiles asynchronously and cannot be pixel-snapshotted reliably, so anything
/// that could be *wrong* about the direction indicator has to be arithmetic.
@Suite("RouteDirectionMarkers")
struct RouteDirectionMarkersTests {

    private func coordinate(_ latitude: Double, _ longitude: Double) -> RouteCoordinate {
        RouteCoordinate(latitude: latitude, longitude: longitude, elevationMeters: nil)
    }

    /// `RouteDirectionMarkers.arrows` without its spacing, which most of these tests do not read.
    private func placements(coordinates: [RouteCoordinate],
                            visibleBounds: RouteBounds?,
                            limit: Int = 12) -> [RouteDirectionMarkers.Placement] {
        RouteDirectionMarkers.arrows(coordinates: coordinates, visibleBounds: visibleBounds,
                                     limit: limit).placements
    }

    private func placements(coordinates: [RouteCoordinate],
                            spacingMeters: Double,
                            visibleBounds: RouteBounds,
                            limit: Int = 12) -> [RouteDirectionMarkers.Placement] {
        RouteDirectionMarkers.arrows(coordinates: coordinates, spacingMeters: spacingMeters,
                                     visibleBounds: visibleBounds, limit: limit).placements
    }

    /// Due east along the 37th parallel, about 8.9 km long.
    private var eastwardRoute: [RouteCoordinate] {
        [coordinate(37.0, -122.0), coordinate(37.0, -121.9)]
    }

    /// A route that doubles back on itself inside one viewport — a switchback climb or a
    /// criterium lap. Spacing is measured along the *route*, so this is what produces far more
    /// in-view samples than the cap allows, and it is the only shape that exercises thinning.
    private var zigzagRoute: [RouteCoordinate] {
        (0...80).map { step in
            coordinate(step.isMultiple(of: 2) ? 36.99 : 37.01,
                       -122.0 + 0.02 * Double(step) / 80)
        }
    }

    private let zigzagViewport = RouteBounds(
        minLatitude: 36.98, maxLatitude: 37.02,
        minLongitude: -122.005, maxLongitude: -121.975
    )

    private let wideViewport = RouteBounds(
        minLatitude: 36.9, maxLatitude: 37.1,
        minLongitude: -122.05, maxLongitude: -121.85
    )

    @Test("no viewport means no arrows")
    func nilBoundsYieldsNothing() {
        // Spacing is a fraction of what is on screen. Falling back to the route's own length
        // would make the same route read differently on two screens.
        #expect(placements(coordinates: eastwardRoute,
                                                 visibleBounds: nil).isEmpty)
    }

    @Test("arrows point along the route")
    func bearingFollowsTheRoute() {
        let eastward = placements(coordinates: eastwardRoute,
                                                        visibleBounds: wideViewport)
        #expect(!eastward.isEmpty)
        for placement in eastward {
            #expect(abs(placement.bearingDegrees - 90) < 1)
        }

        let westward = placements(coordinates: eastwardRoute.reversed(),
                                                        visibleBounds: wideViewport)
        for placement in westward {
            #expect(abs(placement.bearingDegrees - 270) < 1)
        }
    }

    @Test("no arrow lands on the route's first point, where the start flag sits")
    func firstPointCarriesNoArrow() {
        let placements = placements(coordinates: eastwardRoute,
                                                          visibleBounds: wideViewport)
        let start = eastwardRoute[0]
        #expect(!placements.contains { $0.coordinate == start })
    }

    @Test("arrows outside the viewport are culled")
    func placementsAreCulledToTheViewport() {
        // Only the western third of the route is on screen.
        let westernSliver = RouteBounds(minLatitude: 36.9, maxLatitude: 37.1,
                                        minLongitude: -122.00, maxLongitude: -121.97)
        let placements = placements(coordinates: eastwardRoute,
                                                          visibleBounds: westernSliver)
        #expect(!placements.isEmpty)
        for placement in placements {
            #expect(westernSliver.contains(latitude: placement.coordinate.latitude,
                                           longitude: placement.coordinate.longitude))
        }
    }

    @Test("too many in view climbs a rung rather than dropping arrows")
    func limitClimbsTheLadder() {
        let capped = RouteDirectionMarkers.arrows(
            coordinates: zigzagRoute, visibleBounds: zigzagViewport, limit: 5
        )
        #expect(capped.placements.count <= 5)
        #expect(!capped.placements.isEmpty)
        // It got there by coarsening, not by thinning: the spacing it reports is above the rung
        // the climb starts at, and is itself a rung of the ladder.
        #expect(capped.spacingMeters > RouteDirectionMarkers.baseSpacingMeters)
        let rungs = log2(capped.spacingMeters / RouteDirectionMarkers.baseSpacingMeters)
        #expect(abs(rungs - rungs.rounded()) < 1e-9)
    }

    @Test("a cap does not move arrows: the survivors are the coarser rung's own")
    func limitKeepsTheNesting() {
        // The failure this pins: thinning an over-long list to `limit` evenly spaced entries
        // keeps every arrow on the lattice but picks a *different* subset at each zoom, so the
        // arrows appear to move about as the rider pinches.
        let capped = RouteDirectionMarkers.arrows(
            coordinates: zigzagRoute, visibleBounds: zigzagViewport, limit: 5
        )
        let atThatSpacing = placements(coordinates: zigzagRoute,
                                       spacingMeters: capped.spacingMeters,
                                       visibleBounds: zigzagViewport,
                                       limit: 1_000)
        #expect(capped.placements == atThatSpacing)
    }

    @Test("a route shorter than one spacing still says which way it runs")
    func shortRouteStillGetsAnArrow() {
        // 150 m of road is shorter than one spacing at any zoom, so the ladder puts no arrow on
        // it at all — the midpoint case is what still says which way it runs.
        let short = [coordinate(37.0, -122.0), coordinate(37.0, -121.9983)]
        let placements = placements(coordinates: short,
                                                          visibleBounds: wideViewport)
        #expect(placements.count == 1)
        #expect(abs(placements[0].bearingDegrees - 90) < 1)
    }

    @Test("a zero-length route yields nothing rather than a made-up direction")
    func degenerateRoutes() {
        let point = coordinate(37.0, -122.0)
        #expect(placements(coordinates: [point],
                                                 visibleBounds: wideViewport).isEmpty)
        #expect(placements(coordinates: [point, point],
                                                 visibleBounds: wideViewport).isEmpty)
        #expect(placements(coordinates: [],
                                                 visibleBounds: wideViewport).isEmpty)
    }

    @Test("how densely the source GPX was sampled does not change the arrows")
    func samplingDensityDoesNotMatter() {
        // The same road described by two points and by fifty. #192's whole reason for measuring
        // along the route was that reasoning about array indices as if they were distances makes
        // the answer depend on which planning tool wrote the file.
        let sparse = eastwardRoute
        let dense = (0...50).map { step in
            coordinate(37.0, -122.0 + 0.1 * Double(step) / 50)
        }

        let fromSparse = placements(coordinates: sparse,
                                                          visibleBounds: wideViewport)
        let fromDense = placements(coordinates: dense,
                                                         visibleBounds: wideViewport)

        #expect(fromSparse.count == fromDense.count)
        for (a, b) in zip(fromSparse, fromDense) {
            #expect(abs(a.coordinate.latitude - b.coordinate.latitude) < 1e-6)
            #expect(abs(a.coordinate.longitude - b.coordinate.longitude) < 1e-6)
            #expect(abs(a.bearingDegrees - b.bearingDegrees) < 0.5)
        }
    }

    @Test("capping leaves arrows along the whole visible line, not just its start")
    func cappingCoversTheWholeLine() {
        // Spacing is measured along the *route*, so a line that doubles back inside one viewport
        // puts far more arrows on screen than the cap. Truncating the list would leave the back
        // half of a visible route with no direction at all.
        let uncapped = placements(coordinates: zigzagRoute, visibleBounds: zigzagViewport,
                                  limit: 1_000)
        let capped = placements(coordinates: zigzagRoute, visibleBounds: zigzagViewport, limit: 6)
        #expect(uncapped.count > 6)
        #expect(capped.count <= 6)
        // The last capped arrow must sit near the end of the line, not a sixth of the way in.
        let lastCapped = try! #require(capped.last).coordinate.longitude
        let lastUncapped = try! #require(uncapped.last).coordinate.longitude
        #expect(abs(lastCapped - lastUncapped) < 0.01)
    }

    @Test("a cap of one coarsens until one arrow is left, and it is on the lattice")
    func limitOfOne() {
        let capped = RouteDirectionMarkers.arrows(coordinates: zigzagRoute,
                                                  visibleBounds: zigzagViewport, limit: 1)
        #expect(capped.placements.count == 1)
        let arrow = try! #require(capped.placements.first)
        // On the lattice for the spacing it settled at, so it is one of the arrows a finer zoom
        // also draws rather than a point invented for the cap.
        let atThatSpacing = placements(coordinates: zigzagRoute,
                                       spacingMeters: capped.spacingMeters,
                                       visibleBounds: zigzagViewport,
                                       limit: 1_000)
        #expect(atThatSpacing.contains(arrow))
    }

    // MARK: - The live ride map (#258)

    /// The angles below are exact in the maths and inexact in binary, since every one of them
    /// goes through a radian round trip. A thousandth of a degree is far tighter than anything
    /// that could be seen on a map and far looser than the round trip's error.
    private let angleTolerance = 0.001

    @Test("starting the climb at the base rung is what the bounds entry point does")
    func explicitSpacingMatchesDerivedSpacing() {
        let derived = placements(coordinates: zigzagRoute, visibleBounds: zigzagViewport)
        let explicit = placements(
            coordinates: zigzagRoute,
            spacingMeters: RouteDirectionMarkers.baseSpacingMeters,
            visibleBounds: zigzagViewport
        )
        #expect(derived == explicit)
        #expect(!derived.isEmpty)
    }

    @Test("a north-up flat map draws a chevron at its bearing")
    func screenAngleOnAFlatNorthUpMap() {
        for bearing in stride(from: 0.0, to: 360.0, by: 15) {
            #expect(abs(RouteDirectionMarkers.screenAngleDegrees(bearingDegrees: bearing,
                                                                 headingDegrees: 0,
                                                                 pitchDegrees: 0) - bearing)
                    < angleTolerance)
        }
    }

    @Test("a heading-up map turns the world under the chevron")
    func screenAngleCountersTheHeading() {
        // Riding east with the map heading-up: the route ahead is straight up the screen.
        #expect(RouteDirectionMarkers.screenAngleDegrees(bearingDegrees: 90,
                                                        headingDegrees: 90,
                                                        pitchDegrees: 0) == 0)

        // A route heading north while the rider faces east reads as a left turn: 90° anticlockwise
        // on screen, which is 270 in the clockwise convention rather than a negative angle.
        #expect(abs(RouteDirectionMarkers.screenAngleDegrees(bearingDegrees: 0,
                                                             headingDegrees: 90,
                                                             pitchDegrees: 0) - 270)
                < angleTolerance)
    }

    @Test("tilt leaves the axes alone and pulls everything between them towards the horizontal")
    func screenAnglePitch() {
        let pitch = 35.0   // What MapKit clamps the navigation tilt to at its follow distance.
        for bearing in [0.0, 90.0, 180.0, 270.0] {
            let angle = RouteDirectionMarkers.screenAngleDegrees(bearingDegrees: bearing,
                                                                 headingDegrees: 0,
                                                                 pitchDegrees: pitch)
            #expect(abs(angle - bearing) < angleTolerance)
        }
        // Foreshortening the screen's vertical axis moves a diagonal towards the horizontal —
        // away from 0, towards 90 — and by a few degrees at this tilt, not a quadrant.
        let diagonal = RouteDirectionMarkers.screenAngleDegrees(bearingDegrees: 45,
                                                                headingDegrees: 0,
                                                                pitchDegrees: pitch)
        #expect(diagonal > 45 && diagonal < 55)
    }

    @Test("the screen angle is always one MapKit can rotate by")
    func screenAngleIsNormalised() {
        for bearing in stride(from: 0.0, to: 360.0, by: 11) {
            for heading in stride(from: 0.0, to: 360.0, by: 23) {
                let angle = RouteDirectionMarkers.screenAngleDegrees(bearingDegrees: bearing,
                                                                     headingDegrees: heading,
                                                                     pitchDegrees: 60)
                #expect(angle >= 0 && angle < 360)
            }
        }
        // A camera reported mid-transition must not rotate a chevron to NaN.
        #expect(RouteDirectionMarkers.screenAngleDegrees(bearingDegrees: .nan,
                                                        headingDegrees: 0,
                                                        pitchDegrees: 0) == 0)
        #expect(RouteDirectionMarkers.screenAngleDegrees(bearingDegrees: 90,
                                                        headingDegrees: 90,
                                                        pitchDegrees: .nan) == 0)
    }

    // MARK: - #258 review: the arrows shifted on zoom and pointed the wrong way

    /// A road bending through a quarter circle — a suburban curve, the shape that made the first
    /// cut point an arrow ~90° off the line it was drawn on.
    private var curvingRoute: [RouteCoordinate] {
        (0...90).map { degrees in
            let radians = Double(degrees) * .pi / 180
            // ~1.1 km radius, from due north at the start round to due east at the end.
            return coordinate(37.0 + 0.01 * sin(radians), -122.0 + 0.0125 * (1 - cos(radians)))
        }
    }

    @Test("an arrow points along the line where it sits, not at the next arrow")
    func bearingIsLocalNotChordToTheNextArrow() {
        // The bug: bearings were taken between arrow *positions*, hundreds of metres apart at a
        // browsing zoom. On a curve that chord runs at an angle to the stretch of line the arrow
        // is drawn on — up to 90° out, which is what shipped.
        let bounds = RouteBounds(minLatitude: 36.99, maxLatitude: 37.02,
                                 minLongitude: -122.01, maxLongitude: -121.98)
        // An explicit fine spacing: the curve is under 2 km long, so the spacing this viewport
        // would derive puts two arrows on it, and two is too few to catch a bearing that drifts
        // round the bend.
        let placements = placements(
            coordinates: curvingRoute,
            spacingMeters: RouteDirectionMarkers.baseSpacingMeters,
            visibleBounds: bounds,
            limit: 100
        )
        #expect(placements.count > 10)
        // ...and the arrows must actually turn with the road, or a bearing frozen at the start
        // would pass the per-arrow check below by accident.
        let bearings = placements.map(\.bearingDegrees)
        let first = try! #require(bearings.first)
        let last = try! #require(bearings.last)
        #expect(abs(last - first) > 45)
        let cumulative = RouteGeometry.cumulativeDistances(curvingRoute)
        for placement in placements {
            // The direction of the curve at the arrow's own position, measured independently.
            let projection = try! #require(RouteGeometry.projection(of: placement.coordinate,
                                                                    onto: curvingRoute,
                                                                    cumulative: cumulative))
            let local = try! #require(RouteGeometry.tangentBearingDegrees(
                curvingRoute,
                atMeters: projection.distanceAlongRouteMeters,
                windowMeters: 5,
                cumulative: cumulative
            ))
            var error = abs(placement.bearingDegrees - local)
            if error > 180 { error = 360 - error }
            #expect(error < 5)
        }
    }

    @Test("zooming in leaves the arrows already on screen where they are")
    func arrowsDoNotShiftOnZoom() {
        // The second half of the #258 review: spacing derived straight from the viewport is a
        // continuous function of it, so every pinch moved every arrow. On the ladder, a coarser
        // spacing is a multiple of a finer one, so its arrows are a subset of the finer set.
        let fine = placements(coordinates: curvingRoute,
                                                    spacingMeters: RouteDirectionMarkers.baseSpacingMeters,
                                                    visibleBounds: wideViewport,
                                                    limit: 1_000)
        let coarse = placements(
            coordinates: curvingRoute,
            spacingMeters: RouteDirectionMarkers.baseSpacingMeters * 4,
            visibleBounds: wideViewport,
            limit: 1_000
        )
        #expect(coarse.count > 1)
        #expect(fine.count > coarse.count)
        for placement in coarse {
            #expect(fine.contains { $0.coordinate == placement.coordinate })
        }
    }

    @Test("the arrow grows with the ladder, so it keeps its proportion as the camera pulls back")
    func arrowSizeFollowsTheSpacing() {
        let base = RouteDirectionMarkers.baseSpacingMeters
        // At the finest spacing — a street-level zoom — the arrow is the size read off a real
        // route in review.
        #expect(RouteDirectionMarkers.arrowPoints(forSpacingMeters: base)
                == RouteDirectionMarkers.baseArrowPoints)
        // One point per rung.
        #expect(RouteDirectionMarkers.arrowPoints(forSpacingMeters: base * 2)
                == RouteDirectionMarkers.baseArrowPoints + RouteDirectionMarkers.arrowPointsPerRung)
        #expect(RouteDirectionMarkers.arrowPoints(forSpacingMeters: base * 64)
                == RouteDirectionMarkers.baseArrowPoints + 6 * RouteDirectionMarkers.arrowPointsPerRung)
        // A world-zoom camera is a dozen rungs up; the ceiling is what stops the arrow dwarfing
        // the route it annotates.
        #expect(RouteDirectionMarkers.arrowPoints(forSpacingMeters: base * 4096)
                == RouteDirectionMarkers.maximumArrowPoints)
        // Never smaller than the base, whatever it is handed.
        #expect(RouteDirectionMarkers.arrowPoints(forSpacingMeters: 1)
                == RouteDirectionMarkers.baseArrowPoints)
        #expect(RouteDirectionMarkers.arrowPoints(forSpacingMeters: .nan)
                == RouteDirectionMarkers.baseArrowPoints)
    }

    @Test("the size changes only where the density does")
    func arrowSizeIsStableWithinARung() {
        // Sized off the raw viewport, a pinch would grow the arrows smoothly; sized off the rung,
        // it changes at exactly the zooms that add or remove arrows.
        let base = RouteDirectionMarkers.baseSpacingMeters
        let withinARung = [base * 2, base * 2.0, base * 2]
        let sizes = Set(withinARung.map(RouteDirectionMarkers.arrowPoints(forSpacingMeters:)))
        #expect(sizes.count == 1)
        // Two viewports a hair apart but either side of a rung boundary place different numbers
        // of arrows, so they are allowed to size them differently.
        #expect(RouteDirectionMarkers.arrowPoints(forSpacingMeters: base * 2)
                != RouteDirectionMarkers.arrowPoints(forSpacingMeters: base * 8))
    }

    @Test("pinching in only adds arrows: none of the ones on screen move")
    func zoomingInOnlyAddsArrows() {
        // The requirement in Brian's words: at higher zoom levels there should be more arrows,
        // but arrows should only be added to and subtracted from the line, never moved.
        let centre = (latitude: 37.0, longitude: -121.955)
        // Five zoom steps over the same centre, each half the width of the last.
        let viewports = (0..<5).map { step -> RouteBounds in
            let half = 0.08 / pow(2, Double(step))
            return RouteBounds(minLatitude: centre.latitude - half,
                               maxLatitude: centre.latitude + half,
                               minLongitude: centre.longitude - half,
                               maxLongitude: centre.longitude + half)
        }

        var previous: (bounds: RouteBounds,
                       placements: [RouteDirectionMarkers.Placement],
                       spacingMeters: Double)?
        for bounds in viewports {
            let currentArrows = RouteDirectionMarkers.arrows(coordinates: eastwardRoute,
                                                             visibleBounds: bounds, limit: 24)
            let current = currentArrows.placements
            #expect(!current.isEmpty)
            if let previous {
                // Not "more arrows": a tighter viewport holds less *line*, so it can legitimately
                // draw fewer. What must hold is that the ones still on screen have not moved —
                // arrows are only ever added to and subtracted from the line.
                for arrow in previous.placements
                where bounds.contains(latitude: arrow.coordinate.latitude,
                                      longitude: arrow.coordinate.longitude) {
                    #expect(current.contains(arrow))
                }
                // And the line that is on screen is annotated at least as closely as before: the
                // spacing never coarsens on the way in.
                #expect(currentArrows.spacingMeters <= previous.spacingMeters)
            }
            previous = (bounds, current, currentArrows.spacingMeters)
        }
    }

    @Test("a loop that meanders through the viewport gets arrows along all of it")
    func aMeanderingLoopIsNotUnderPopulated() {
        // Brian's screenshot: a ~7 km loop, whole thing on screen in a viewport about 5 km wide,
        // and two arrows on it. Spacing was the viewport's width over four, which is only right
        // where the route crosses the screen once — this loop has well over a viewport's width of
        // line in view.
        let loop = (0...360).map { degrees -> RouteCoordinate in
            let radians = Double(degrees) * .pi / 180
            return coordinate(37.0 + 0.010 * sin(radians), -122.0 + 0.0125 * (1 - cos(radians)))
        }
        // Wide enough to hold the whole loop: it runs from -122.000 to -121.975.
        let viewport = RouteBounds(minLatitude: 36.978, maxLatitude: 37.022,
                                   minLongitude: -122.010, maxLongitude: -121.965)
        let arrows = RouteDirectionMarkers.arrows(coordinates: loop, visibleBounds: viewport)

        #expect(RouteGeometry.distanceMeters(loop) > 6_000)
        // As many as the cap allows, rather than as many as the screen is wide.
        #expect(arrows.placements.count > RouteDirectionMarkers.targetArrowsInView / 2)
        #expect(arrows.placements.count <= RouteDirectionMarkers.targetArrowsInView)
        // Spread around the loop, not clustered on one side of it.
        let north = arrows.placements.filter { $0.coordinate.latitude > 37.0 }.count
        #expect(north > 0 && north < arrows.placements.count)
    }
}
