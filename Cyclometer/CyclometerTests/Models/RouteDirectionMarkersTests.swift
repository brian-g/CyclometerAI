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

    @Test("spacing is a fraction of the viewport, so zooming in brings arrows closer together")
    func spacingScalesWithTheViewport() {
        let zoomedOut = RouteDirectionMarkers.spacingMeters(for: wideViewport)
        let zoomedIn = RouteDirectionMarkers.spacingMeters(
            for: RouteBounds(minLatitude: 36.99, maxLatitude: 37.01,
                             minLongitude: -122.01, maxLongitude: -121.99)
        )
        #expect(zoomedIn < zoomedOut)
        // ~17.8 km of longitude at this latitude, shared out over however many arrows the
        // constant asks for, then rounded up to the next rung of the ladder (#258 review) —
        // read from the constants so tuning the density does not silently invalidate this.
        #expect(zoomedOut == RouteDirectionMarkers.quantized(
            17_800 / RouteDirectionMarkers.arrowsAcrossViewport
        ))
    }

    @Test("spacing never falls below the base rung, however far the rider zooms in")
    func spacingIsFloored() {
        let tiny = RouteBounds(minLatitude: 37.0, maxLatitude: 37.0001,
                               minLongitude: -122.0, maxLongitude: -121.9999)
        #expect(RouteDirectionMarkers.spacingMeters(for: tiny)
                == RouteDirectionMarkers.baseSpacingMeters)
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
        // It got there by coarsening, not by thinning: the spacing it reports is above the one
        // the viewport asked for, and it is still a rung of the ladder.
        let asked = RouteDirectionMarkers.spacingMeters(for: zigzagViewport)
        #expect(capped.spacingMeters > asked)
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

    @Test("camera distance sets the spacing, on the same ladder as a viewport does")
    func cameraDistanceSpacing() {
        // Far enough out that the fraction-of-the-viewport rule governs, rounded to its rung.
        #expect(RouteDirectionMarkers.spacingMeters(forCameraDistanceMeters: 4_000)
                == RouteDirectionMarkers.quantized(
                    4_000 / RouteDirectionMarkers.arrowsAcrossViewport
                ))
        // Close in, the base rung is what stops a widget following the rider from asking for an
        // arrow every few metres.
        #expect(RouteDirectionMarkers.spacingMeters(forCameraDistanceMeters: 200)
                == RouteDirectionMarkers.baseSpacingMeters)
        // MapKit has been known to report a camera mid-transition; neither a zero nor a
        // non-finite distance may produce a spacing the placement walk would spin on.
        #expect(RouteDirectionMarkers.spacingMeters(forCameraDistanceMeters: 0)
                == RouteDirectionMarkers.baseSpacingMeters)
        #expect(RouteDirectionMarkers.spacingMeters(forCameraDistanceMeters: .nan)
                == RouteDirectionMarkers.baseSpacingMeters)
        #expect(RouteDirectionMarkers.spacingMeters(forCameraDistanceMeters: -1)
                == RouteDirectionMarkers.baseSpacingMeters)
    }

    @Test("a spacing passed in places the same arrows a viewport would derive")
    func explicitSpacingMatchesDerivedSpacing() {
        let derived = placements(coordinates: zigzagRoute,
                                                       visibleBounds: zigzagViewport)
        let explicit = placements(
            coordinates: zigzagRoute,
            spacingMeters: RouteDirectionMarkers.spacingMeters(for: zigzagViewport),
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

    @Test("every spacing the viewport can ask for lands on a rung of the same ladder")
    func spacingIsAlwaysOnTheLadder() {
        let base = RouteDirectionMarkers.baseSpacingMeters
        for desired in stride(from: 10.0, through: 20_000.0, by: 137.0) {
            let spacing = RouteDirectionMarkers.quantized(desired)
            #expect(spacing >= base)
            // A power-of-two multiple of the base, and never finer than asked for by more than
            // one rung.
            let rungs = log2(spacing / base)
            #expect(abs(rungs - rungs.rounded()) < 1e-9)
            #expect(spacing >= desired || spacing == base)
        }
        #expect(RouteDirectionMarkers.quantized(.nan) == base)
        #expect(RouteDirectionMarkers.quantized(0) == base)
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
        #expect(RouteDirectionMarkers.arrowPoints(
            forSpacingMeters: RouteDirectionMarkers.quantized(base * 1.9)
        ) != RouteDirectionMarkers.arrowPoints(
            forSpacingMeters: RouteDirectionMarkers.quantized(base * 4.1)
        ))
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

        var previous: (bounds: RouteBounds, placements: [RouteDirectionMarkers.Placement])?
        for bounds in viewports {
            let current = placements(coordinates: eastwardRoute, visibleBounds: bounds, limit: 24)
            #expect(!current.isEmpty)
            if let previous {
                // Zooming in never draws fewer.
                #expect(current.count >= previous.placements.count)
                // And every arrow that was on screen and still is, is in the same place.
                for arrow in previous.placements
                where bounds.contains(latitude: arrow.coordinate.latitude,
                                      longitude: arrow.coordinate.longitude) {
                    #expect(current.contains(arrow))
                }
            }
            previous = (bounds, current)
        }
    }
}
