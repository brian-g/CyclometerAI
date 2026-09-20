import CoreLocation
import MapKit
import SwiftUI
import Testing
@testable import Cyclometer

@Suite("LiveMapCamera — the live ride map's camera (#199)")
struct LiveMapCameraTests {

    private let centre = CLLocationCoordinate2D(latitude: 43.0731, longitude: -89.4012)
    private var current: MapCamera {
        MapCamera(centerCoordinate: centre, distance: 1663, heading: 137, pitch: 0)
    }
    private let plainFollow = MapCameraPosition.userLocation(followsHeading: false, fallback: .automatic)

    /// 800 m north, then 400 m east: the #197 simulator-drive route.
    private let route = [
        RouteCoordinate(latitude: 43.0731, longitude: -89.4012, elevationMeters: nil),
        RouteCoordinate(latitude: 43.0803, longitude: -89.4012, elevationMeters: nil),
        RouteCoordinate(latitude: 43.0803, longitude: -89.3963, elevationMeters: nil)
    ]

    // MARK: Surfaces and modes

    @Test("The widget takes no gestures and shows no controls, so nothing on it can leave follow (#62)")
    func widgetHasNoNativeControlsOrGestures() {
        #expect(LiveMapCamera.Surface.widget.interactionModes.isEmpty)
        #expect(!LiveMapCamera.Surface.widget.showsControls)
        #expect(LiveMapCamera.Surface.sheet.interactionModes == .all)
        #expect(LiveMapCamera.Surface.sheet.showsControls)
    }

    @Test("The widget is heading-up whatever the saved orientation",
          arguments: [MapOrientation.headingUp, .northUp], [false, true])
    func widgetIgnoresSavedOrientation(_ orientation: MapOrientation, hasRoute: Bool) {
        #expect(LiveMapCamera.mode(surface: .widget, orientation: orientation, hasRoute: hasRoute).followsHeading)
    }

    @Test("The sheet opens in the saved orientation")
    func sheetOpensInSavedOrientation() {
        #expect(LiveMapCamera.mode(surface: .sheet, orientation: .headingUp, hasRoute: false).followsHeading)
        #expect(!LiveMapCamera.mode(surface: .sheet, orientation: .northUp, hasRoute: false).followsHeading)
    }

    @Test("A loaded route tilts both surfaces, in both orientations",
          arguments: LiveMapCamera.Surface.allCases, [MapOrientation.headingUp, .northUp])
    func routeTiltsBothSurfacesBothOrientations(_ surface: LiveMapCamera.Surface, _ orientation: MapOrientation) {
        let mode = LiveMapCamera.mode(surface: surface, orientation: orientation, hasRoute: true)
        #expect(mode.pitch == LiveMapCamera.navigationPitchDegrees)
    }

    @Test("Without a route the map stays flat",
          arguments: LiveMapCamera.Surface.allCases, [MapOrientation.headingUp, .northUp])
    func noRouteStaysFlat(_ surface: LiveMapCamera.Surface, _ orientation: MapOrientation) {
        #expect(LiveMapCamera.mode(surface: surface, orientation: orientation, hasRoute: false).pitch == 0)
    }

    // MARK: Seeding and following

    /// With no route the widget needs no seed at all, so a free ride's map starts the way it did before #199.
    @Test("Only a tilt or a turn to north needs a seed")
    func onlyTiltOrNorthUpNeedsSeed() {
        #expect(!LiveMapCamera.needsSeed(.init(followsHeading: true, pitch: 0)))
        #expect(LiveMapCamera.needsSeed(.init(followsHeading: true, pitch: LiveMapCamera.navigationPitchDegrees)))
        #expect(LiveMapCamera.needsSeed(.init(followsHeading: false, pitch: 0)))
    }

    @Test("A seed keeps the camera's centre and distance, and applies the tilt")
    func seedKeepsCentreAndDistance() {
        let mode = LiveMapCamera.Mode(followsHeading: true, pitch: LiveMapCamera.navigationPitchDegrees)
        let seed = LiveMapCamera.seed(from: current, mode: mode)
        #expect(seed.centerCoordinate.latitude == centre.latitude)
        #expect(seed.centerCoordinate.longitude == centre.longitude)
        #expect(seed.distance == 1663)
        #expect(seed.pitch == LiveMapCamera.navigationPitchDegrees)
    }

    @Test("A north-up seed turns the camera to north; a heading-up seed leaves the heading to follow")
    func northUpSeedZeroesHeading() {
        let northUp = LiveMapCamera.seed(from: current, mode: .init(followsHeading: false, pitch: 0))
        let headingUp = LiveMapCamera.seed(from: current, mode: .init(followsHeading: true, pitch: 0))
        #expect(northUp.heading == 0)
        #expect(headingUp.heading == 137)
    }

    @Test("Following matches the mode's heading", arguments: [false, true])
    func followMatchesMode(_ followsHeading: Bool) {
        let position = LiveMapCamera.follow(.init(followsHeading: followsHeading, pitch: 0))
        #expect(position.followsUserLocation)
        #expect(position.followsUserHeading == followsHeading)
    }

    // MARK: Correction

    @Test("A widget knocked out of heading-up follow is put back")
    func widgetDowngradeIsCorrected() {
        let mode = LiveMapCamera.mode(surface: .widget, orientation: .northUp, hasRoute: true)
        #expect(LiveMapCamera.needsCorrection(surface: .widget, position: plainFollow, mode: mode))
        #expect(LiveMapCamera.needsCorrection(surface: .widget, position: .camera(current), mode: mode))
        #expect(!LiveMapCamera.needsCorrection(surface: .widget, position: LiveMapCamera.follow(mode), mode: mode))
    }

    @Test("The sheet is left where the rider put it")
    func sheetDowngradeIsLeftAlone() {
        let mode = LiveMapCamera.mode(surface: .sheet, orientation: .headingUp, hasRoute: false)
        #expect(!LiveMapCamera.needsCorrection(surface: .sheet, position: .camera(current), mode: mode))
        #expect(!LiveMapCamera.needsCorrection(surface: .sheet, position: plainFollow, mode: mode))
    }

    // MARK: The orientation button

    @Test("Following in the saved orientation, a tap switches it", arguments: [MapOrientation.headingUp, .northUp])
    func tapWhileFollowingToggles(_ saved: MapOrientation) {
        let position = MapCameraPosition.userLocation(followsHeading: saved == .headingUp, fallback: .automatic)
        #expect(LiveMapCamera.orientationTap(position: position, saved: saved) == .toggle)
    }

    @Test("After a pan or the route overview, a tap brings the saved orientation back")
    func tapAfterPanReengages() throws {
        let overview = try #require(LiveMapCamera.overviewRegion(route: route))
        #expect(LiveMapCamera.orientationTap(position: .camera(current), saved: .headingUp) == .reengage)
        #expect(LiveMapCamera.orientationTap(position: .region(overview), saved: .northUp) == .reengage)
    }

    @Test("After the compass or re-centre drops heading, a tap brings heading-up back instead of switching")
    func tapAfterCompassDowngradeReengages() {
        #expect(LiveMapCamera.orientationTap(position: plainFollow, saved: .headingUp) == .reengage)
    }

    // MARK: Route overview

    @Test("The overview contains every point of the route, with room around it")
    func overviewContainsEveryRoutePoint() throws {
        let region = try #require(LiveMapCamera.overviewRegion(route: route))
        for point in route {
            #expect(abs(point.latitude - region.center.latitude) <= region.span.latitudeDelta / 2)
            #expect(abs(point.longitude - region.center.longitude) <= region.span.longitudeDelta / 2)
        }
        let bounds = RouteGeometry.boundingBox(route)
        #expect(region.span.latitudeDelta > bounds.maxLatitude - bounds.minLatitude)
        #expect(region.span.longitudeDelta > bounds.maxLongitude - bounds.minLongitude)
    }

    @Test("A route too small to frame gets the minimum span; fewer than two points gets no overview")
    func overviewFloorsTinyRoute() throws {
        let tiny = [route[0], RouteCoordinate(latitude: 43.07311, longitude: -89.4012, elevationMeters: nil)]
        let region = try #require(LiveMapCamera.overviewRegion(route: tiny))
        #expect(region.span.latitudeDelta >= RoutesMapCamera.minimumSpanDegrees)
        #expect(region.span.longitudeDelta >= RoutesMapCamera.minimumSpanDegrees)
        #expect(LiveMapCamera.overviewRegion(route: [route[0]]) == nil)
        #expect(LiveMapCamera.overviewRegion(route: []) == nil)
    }


    // MARK: - The viewport the arrows are counted against (#258 review)

    @Test("the arrow viewport comes from the camera distance, not the pitched region")
    func visibleBoundsFollowTheCameraDistance() {
        let camera = MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
            distance: 2_000,
            heading: 0,
            pitch: 60
        )
        let bounds = try! #require(LiveMapCamera.visibleBounds(for: camera))
        // A box about one camera distance across, centred where the camera looks.
        #expect(abs(bounds.center.latitude - 37.0) < 1e-6)
        #expect(abs(bounds.center.longitude + 122.0) < 1e-6)
        let heightMeters = (bounds.maxLatitude - bounds.minLatitude) * 111_320
        #expect(abs(heightMeters - 2_000) < 50)
        // The tilt must not widen it: a pitched region runs to the horizon, which is the whole
        // reason this exists.
        let flat = MapCamera(centerCoordinate: camera.centerCoordinate, distance: 2_000,
                             heading: 0, pitch: 0)
        #expect(LiveMapCamera.visibleBounds(for: flat) == bounds)
    }

    @Test("a camera mid-transition yields no viewport rather than a degenerate one")
    func visibleBoundsRefusesANonsenseCamera() {
        let stalled = MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
            distance: 0,
            heading: 0,
            pitch: 0
        )
        #expect(LiveMapCamera.visibleBounds(for: stalled) == nil)
    }
}
