import MapKit
import SwiftUI

/// How the live ride map's camera behaves (#199): which way up it draws the world, whether it tilts,
/// when it must be put back on the rider, and what the sheet's orientation button does.
///
/// Pure values, like `RoutesMapCamera`. A live `Map` cannot be pixel-snapshot tested reliably, so every
/// decision that could be wrong lives here, with ordinary tests, and `ActiveRideMapView` only applies it.
///
/// # Tilting a camera that follows the rider
///
/// `MapCameraPosition.userLocation(followsHeading:fallback:)` takes no pitch, but it keeps whatever pitch
/// the camera already has. So the view seeds one: a `.camera` where the map is now, tilted (and turned to
/// north for north-up), then `.userLocation` once MapKit reports that camera has landed. On the simulator
/// the tilt held through 670 heading-up and 1,250 north-up samples, and MapKit never took the widget out
/// of follow by itself (#199 spike).
enum LiveMapCamera {

    /// The tilt asked for while a route is loaded. MapKit clamps it to what the camera's distance allows
    /// (35° at its default follow distance), so this is a ceiling rather than the angle drawn.
    static let navigationPitchDegrees = 60.0

    /// How long a seeded camera has to report that it has landed before the view follows anyway. MapKit
    /// reported within 5 ms on every seed in the spike; this only stops a missed report from leaving the
    /// widget parked on a camera that no longer follows the rider.
    static let seedSettleTimeout: Duration = .seconds(1)

    /// The two places the live map appears.
    enum Surface: Equatable, Sendable, CaseIterable {
        /// W8 on the dashboard grid: always heading-up, with neither gestures nor controls, so nothing on
        /// it can take the camera out of follow (#62). A tap opens the sheet.
        case widget
        /// The full-screen sheet: every gesture, MapKit's controls and the sheet's own.
        case sheet

        var interactionModes: MapInteractionModes { self == .sheet ? .all : [] }
        var showsControls: Bool { self == .sheet }
    }

    /// What the camera does while it follows the rider.
    struct Mode: Equatable, Sendable {
        var followsHeading: Bool
        var pitch: Double
    }

    /// The widget ignores the saved orientation; the sheet opens in it. A loaded route tilts both.
    static func mode(surface: Surface, orientation: MapOrientation, hasRoute: Bool) -> Mode {
        Mode(
            followsHeading: surface == .widget || orientation == .headingUp,
            pitch: hasRoute ? navigationPitchDegrees : 0
        )
    }

    /// Whether a map just starting to follow must be seeded. It starts flat, and heading-up follow sets its
    /// own heading, so only a tilt or a turn to north needs one.
    static func needsSeed(_ mode: Mode) -> Bool {
        mode.pitch > 0 || !mode.followsHeading
    }

    /// The camera to seed: where the map is now, at `mode`'s tilt. North-up is turned to north here,
    /// because following without heading keeps whatever heading the camera already has.
    static func seed(from current: MapCamera, mode: Mode) -> MapCamera {
        MapCamera(
            centerCoordinate: current.centerCoordinate,
            distance: current.distance,
            heading: mode.followsHeading ? current.heading : 0,
            pitch: mode.pitch
        )
    }

    /// The position that follows the rider in `mode`.
    static func follow(_ mode: Mode) -> MapCameraPosition {
        .userLocation(followsHeading: mode.followsHeading, fallback: .automatic)
    }

    static func isFollowing(_ position: MapCameraPosition, headingUp: Bool) -> Bool {
        position.followsUserLocation && position.followsUserHeading == headingUp
    }

    /// Whether the map has left `mode`'s follow and must be put back. Only ever the widget: the sheet is
    /// there to be explored, and goes back to following only when the rider asks.
    static func needsCorrection(surface: Surface, position: MapCameraPosition, mode: Mode) -> Bool {
        surface == .widget && !isFollowing(position, headingUp: mode.followsHeading)
    }

    enum OrientationTap: Equatable { case toggle, reengage }

    /// Following in the saved orientation, a tap switches it. Otherwise (after a pan, the route overview,
    /// or re-centre's plain follow) the tap brings the camera back to the saved orientation, so a single
    /// tap always does.
    static func orientationTap(position: MapCameraPosition, saved: MapOrientation) -> OrientationTap {
        isFollowing(position, headingUp: saved == .headingUp) ? .toggle : .reengage
    }

    /// The stretch of ground the arrows should be counted against (#258 review).
    ///
    /// Not `MapCameraUpdateContext.region`: while a route is loaded the map is tilted, and a
    /// pitched camera's region is the axis-aligned box around the whole *frustum* — it runs to
    /// the horizon (`RoutesView`). Counting arrows against that box would count most of the route
    /// as "in view" and coarsen the spacing until the rider had none in front of them.
    ///
    /// `MapCamera.distance` is what the tilt does not touch, so the box is one camera distance
    /// square about where the camera is looking — roughly what fills the screen.
    static func visibleBounds(for camera: MapCamera) -> RouteBounds? {
        guard camera.distance.isFinite, camera.distance > 0 else { return nil }
        return RoutesMapCamera.bounds(for: MKCoordinateRegion(
            center: camera.centerCoordinate,
            latitudinalMeters: camera.distance,
            longitudinalMeters: camera.distance
        ))
    }

    /// The whole route, fitted the way S19 fits its routes. Nil below two points: nothing to frame.
    static func overviewRegion(route: [RouteCoordinate]) -> MKCoordinateRegion? {
        guard route.count > 1 else { return nil }
        return RoutesMapCamera.region(fitting: RouteGeometry.boundingBox(route))
    }
}
