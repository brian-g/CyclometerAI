import Foundation
import Testing
@testable import Cyclometer

/// #194 / #195 — where the direction-of-travel chevrons go.
///
/// The placement is kept out of the `MapContent` precisely so it can be tested here: a live
/// `Map` renders tiles asynchronously and cannot be pixel-snapshotted reliably, so anything
/// that could be *wrong* about the direction indicator has to be arithmetic.
@Suite("RouteDirectionMarkers")
struct RouteDirectionMarkersTests {

    private func coordinate(_ latitude: Double, _ longitude: Double) -> RouteCoordinate {
        RouteCoordinate(latitude: latitude, longitude: longitude, elevationMeters: nil)
    }

    /// Due east along the 37th parallel, about 8.9 km long.
    private var eastwardRoute: [RouteCoordinate] {
        [coordinate(37.0, -122.0), coordinate(37.0, -121.9)]
    }

    private let wideViewport = RouteBounds(
        minLatitude: 36.9, maxLatitude: 37.1,
        minLongitude: -122.05, maxLongitude: -121.85
    )

    @Test("no viewport means no chevrons")
    func nilBoundsYieldsNothing() {
        // Spacing is a fraction of what is on screen. Falling back to the route's own length
        // would make the same route read differently on two screens.
        #expect(RouteDirectionMarkers.placements(coordinates: eastwardRoute,
                                                 visibleBounds: nil).isEmpty)
    }

    @Test("spacing is a fraction of the viewport, so zooming in brings chevrons closer together")
    func spacingScalesWithTheViewport() {
        let zoomedOut = RouteDirectionMarkers.spacingMeters(for: wideViewport)
        let zoomedIn = RouteDirectionMarkers.spacingMeters(
            for: RouteBounds(minLatitude: 36.99, maxLatitude: 37.01,
                             minLongitude: -122.01, maxLongitude: -121.99)
        )
        #expect(zoomedIn < zoomedOut)
        // ~17.8 km of longitude at this latitude, over the eight chevrons asked for.
        #expect(abs(zoomedOut - 17_800 / 8) < 200)
    }

    @Test("spacing never falls below the floor, however far the rider zooms in")
    func spacingIsFloored() {
        let tiny = RouteBounds(minLatitude: 37.0, maxLatitude: 37.0001,
                               minLongitude: -122.0, maxLongitude: -121.9999)
        #expect(RouteDirectionMarkers.spacingMeters(for: tiny)
                == RouteDirectionMarkers.minimumSpacingMeters)
    }

    @Test("chevrons point along the route")
    func bearingFollowsTheRoute() {
        let eastward = RouteDirectionMarkers.placements(coordinates: eastwardRoute,
                                                        visibleBounds: wideViewport)
        #expect(!eastward.isEmpty)
        for placement in eastward {
            #expect(abs(placement.bearingDegrees - 90) < 1)
        }

        let westward = RouteDirectionMarkers.placements(coordinates: eastwardRoute.reversed(),
                                                        visibleBounds: wideViewport)
        for placement in westward {
            #expect(abs(placement.bearingDegrees - 270) < 1)
        }
    }

    @Test("no chevron lands on the route's first point, where the start flag sits")
    func firstPointCarriesNoChevron() {
        let placements = RouteDirectionMarkers.placements(coordinates: eastwardRoute,
                                                          visibleBounds: wideViewport)
        let start = eastwardRoute[0]
        #expect(!placements.contains { $0.coordinate == start })
    }

    @Test("chevrons outside the viewport are culled")
    func placementsAreCulledToTheViewport() {
        // Only the western third of the route is on screen.
        let westernSliver = RouteBounds(minLatitude: 36.9, maxLatitude: 37.1,
                                        minLongitude: -122.00, maxLongitude: -121.97)
        let placements = RouteDirectionMarkers.placements(coordinates: eastwardRoute,
                                                          visibleBounds: westernSliver)
        #expect(!placements.isEmpty)
        for placement in placements {
            #expect(westernSliver.contains(latitude: placement.coordinate.latitude,
                                           longitude: placement.coordinate.longitude))
        }
    }

    @Test("the limit caps how many a single route can draw")
    func limitCapsTheCount() {
        // Zoomed right in on a long route: the spacing floor still yields far more samples than
        // anyone wants as map annotations.
        let longRoute = [coordinate(37.0, -122.0), coordinate(37.0, -120.0)]
        let placements = RouteDirectionMarkers.placements(
            coordinates: longRoute,
            visibleBounds: RouteBounds(minLatitude: 36.9, maxLatitude: 37.1,
                                       minLongitude: -122.0, maxLongitude: -120.0),
            limit: 5
        )
        #expect(placements.count == 5)
    }

    @Test("a route shorter than one spacing still says which way it runs")
    func shortRouteStillGetsAChevron() {
        // 150 m of road with a 2 km spacing resamples to a single point, which would otherwise
        // leave no pair to take a bearing from.
        let short = [coordinate(37.0, -122.0), coordinate(37.0, -121.9983)]
        let placements = RouteDirectionMarkers.placements(coordinates: short,
                                                          visibleBounds: wideViewport)
        #expect(placements.count == 1)
        #expect(abs(placements[0].bearingDegrees - 90) < 1)
    }

    @Test("a zero-length route yields nothing rather than a made-up direction")
    func degenerateRoutes() {
        let point = coordinate(37.0, -122.0)
        #expect(RouteDirectionMarkers.placements(coordinates: [point],
                                                 visibleBounds: wideViewport).isEmpty)
        #expect(RouteDirectionMarkers.placements(coordinates: [point, point],
                                                 visibleBounds: wideViewport).isEmpty)
        #expect(RouteDirectionMarkers.placements(coordinates: [],
                                                 visibleBounds: wideViewport).isEmpty)
    }

    @Test("how densely the source GPX was sampled does not change the chevrons")
    func samplingDensityDoesNotMatter() {
        // The same road described by two points and by fifty. #192's whole reason for
        // `resampled` was that reasoning about array indices as if they were distances makes
        // the answer depend on which planning tool wrote the file.
        let sparse = eastwardRoute
        let dense = (0...50).map { step in
            coordinate(37.0, -122.0 + 0.1 * Double(step) / 50)
        }

        let fromSparse = RouteDirectionMarkers.placements(coordinates: sparse,
                                                          visibleBounds: wideViewport)
        let fromDense = RouteDirectionMarkers.placements(coordinates: dense,
                                                         visibleBounds: wideViewport)

        #expect(fromSparse.count == fromDense.count)
        for (a, b) in zip(fromSparse, fromDense) {
            #expect(abs(a.coordinate.latitude - b.coordinate.latitude) < 1e-6)
            #expect(abs(a.coordinate.longitude - b.coordinate.longitude) < 1e-6)
            #expect(abs(a.bearingDegrees - b.bearingDegrees) < 0.5)
        }
    }

    @Test("capping spreads the chevrons over the whole line rather than truncating it")
    func limitIsSpreadNotTruncated() {
        // Spacing is measured along the *route*, not across the screen, so a line that doubles
        // back inside one viewport yields far more in-view samples than the cap. Taking the
        // first N would leave the back half of a visible route with no direction at all.
        let longRoute = [coordinate(37.0, -122.0), coordinate(37.0, -121.0)]
        let viewport = RouteBounds(minLatitude: 36.9, maxLatitude: 37.1,
                                   minLongitude: -122.0, maxLongitude: -121.0)
        let uncapped = RouteDirectionMarkers.placements(coordinates: longRoute,
                                                        visibleBounds: viewport, limit: 1_000)
        let capped = RouteDirectionMarkers.placements(coordinates: longRoute,
                                                      visibleBounds: viewport, limit: 6)
        #expect(uncapped.count > 6)
        #expect(capped.count == 6)
        // The last capped chevron must sit near the end of the line, not a sixth of the way in.
        let lastCapped = try! #require(capped.last).coordinate.longitude
        let lastUncapped = try! #require(uncapped.last).coordinate.longitude
        #expect(abs(lastCapped - lastUncapped) < 0.01)
    }

    @Test("a cap of one puts its chevron in the middle of the line")
    func limitOfOneDoesNotDivideByZero() {
        let longRoute = [coordinate(37.0, -122.0), coordinate(37.0, -121.0)]
        let viewport = RouteBounds(minLatitude: 36.9, maxLatitude: 37.1,
                                   minLongitude: -122.0, maxLongitude: -121.0)
        let capped = RouteDirectionMarkers.placements(coordinates: longRoute,
                                                      visibleBounds: viewport, limit: 1)
        #expect(capped.count == 1)
        // The middle third of the line: the point is that one chevron lands in the body of the
        // route rather than on its opening stretch, not that it hits the exact halfway metre —
        // placements are indexed from the first sample after the start flag, so the index
        // midpoint sits slightly beyond the geographic one.
        let longitude = try! #require(capped.first).coordinate.longitude
        #expect(longitude < -121.25 && longitude > -121.75)
    }
}
