import SwiftUI
import MapKit

/// The live ride map (#199): the rider's position, the track ridden so far, and the planned route
/// beneath it. It appears on two surfaces:
///
/// - **The W8 widget** (`.widget`) always follows the rider heading-up, takes no gestures and shows no
///   controls, so nothing on it can take the camera out of follow (#62). A tap opens the sheet.
/// - **The full-screen sheet** (`.sheet`) opens in the rider's saved orientation and takes every
///   gesture, with MapKit's controls and the sheet's own.
///
/// While a route is loaded, both tilt into a 3D navigation view. What the camera should do is decided
/// in `LiveMapCamera`; this view only applies it. The map surface bleeds into the safe areas (S05, Map
/// widget safe-area bleed), and the sheet's controls stay inside them.
struct ActiveRideMapView: View {
    /// The recorded track, one array per continuous stretch of riding (#263) — drawn as
    /// one polyline each, so a pause is a gap rather than a chord across it.
    let trackSegments: [[Coordinate]]
    /// The route being ridden, drawn beneath the track. Empty on a free ride.
    let route: [RouteCoordinate]
    let surface: LiveMapCamera.Surface
    /// The sheet's saved orientation. The widget ignores it.
    let orientation: MapOrientation
    let onOrientationToggle: () -> Void

    @State private var position: MapCameraPosition
    /// Where MapKit last reported the camera. `position.camera` is nil while following, so this is the
    /// only source of a seed's centre and distance.
    @State private var camera: MapCamera?
    /// The follow position to take once a seeded camera has landed. Nil outside that moment.
    @State private var pendingFollow: MapCameraPosition?
    /// The camera needs seeding, but MapKit has not yet reported one to seed from.
    @State private var isSeedWanted = false
    /// The route's direction-of-travel arrows (#258), and the viewport they were placed for.
    /// Placing them walks the whole route, so it happens when the camera settles rather than on
    /// every frame; only their rotation follows the camera continuously.
    @State private var arrows = RouteDirectionMarkers.Arrows.none
    @State private var arrowBounds: RouteBounds?
    /// Which way up the arrows are drawn. Its own state, and rounded to the degree, because it is
    /// the one thing that has to follow the camera continuously — writing the whole camera on
    /// every frame would rebuild the track polyline (thousands of points on a long ride) at the
    /// camera's update rate, on a screen that is on for the whole ride.
    @State private var arrowPose = ArrowPose()

    /// The camera pose an arrow is drawn at, to the degree.
    private struct ArrowPose: Equatable {
        var headingDegrees: Double = 0
        var pitchDegrees: Double = 0

        init() {}
        init(_ camera: MapCamera) {
            headingDegrees = camera.heading.rounded()
            pitchDegrees = camera.pitch.rounded()
        }
    }
    @Namespace private var mapScope

    init(
        trackSegments: [[Coordinate]],
        route: [RouteCoordinate] = [],
        surface: LiveMapCamera.Surface = .sheet,
        orientation: MapOrientation = .headingUp,
        onOrientationToggle: @escaping () -> Void = {}
    ) {
        self.trackSegments = trackSegments
        self.route = route
        self.surface = surface
        self.orientation = orientation
        self.onOrientationToggle = onOrientationToggle
        // Following in the right mode from the first frame. Setting it in `onAppear` instead changed the
        // position while the sheet's map was registering its scope, and a sheet opening north-up faulted
        // ("Bound preference MapScopeRegistryKey tried to update multiple times per frame").
        let mode = LiveMapCamera.mode(surface: surface, orientation: orientation, hasRoute: route.count > 1)
        _position = State(initialValue: LiveMapCamera.follow(mode))
    }

    private var mode: LiveMapCamera.Mode {
        LiveMapCamera.mode(surface: surface, orientation: orientation, hasRoute: route.count > 1)
    }

    var body: some View {
        Group {
            if surface.showsControls {
                // Scoped, so the sheet can lay MapKit's controls out in one column with its own. The
                // widget has no controls to scope, and a scope there faulted ("Bound preference
                // MapScopeRegistryKey tried to update multiple times per frame") as the route loaded.
                map(scope: mapScope)
                    .ignoresSafeArea()
                    .overlay(alignment: .topTrailing) { sheetControls }
                    .overlay(alignment: .topLeading) {
                        MapScaleView(scope: mapScope)
                            .padding(Spacing.lg)
                    }
                    .mapControlVisibility(.visible)
                    .mapScope(mapScope)
            } else {
                map(scope: nil)
                    .mapControlVisibility(.hidden)
            }
        }
        .onAppear {
            // A tilt or a turn to north waits for MapKit's first camera report, since there is nothing
            // to seed from until then.
            isSeedWanted = LiveMapCamera.needsSeed(mode)
        }
        .onChange(of: mode) { engage() }
        .onChange(of: position) {
            // The seed parks the camera for a moment on purpose. Anything else that takes the widget
            // out of follow is put straight back.
            if pendingFollow == nil,
               LiveMapCamera.needsCorrection(surface: surface, position: position, mode: mode) {
                engage()
            }
        }
        .task(id: pendingFollow) {
            guard pendingFollow != nil else { return }
            do { try await Task.sleep(for: LiveMapCamera.seedSettleTimeout) } catch { return }
            completeSeed()
        }
    }

    private func map(scope: Namespace.ID?) -> some View {
        Map(position: $position, interactionModes: surface.interactionModes, scope: scope) {
            UserAnnotation()
            // Declared before the track so it draws beneath it: the route ahead, and the track over
            // the part already ridden.
            if route.count > 1 {
                MapPolyline(coordinates: route.map(\.coordinate2D))
                    .stroke(Color.cyMapRoute, lineWidth: Spacing.strokeMapRoute)
            }
            // One polyline per segment. A segment of a single point draws nothing anyway,
            // and `enumerated` rather than the array itself because `[Coordinate]` is not
            // identifiable.
            ForEach(Array(trackSegments.enumerated()), id: \.offset) { _, segment in
                MapPolyline(coordinates: segment.map(\.clLocationCoordinate2D))
                    .stroke(Color.cyMapTravelPath, lineWidth: Spacing.strokeMapTrack)
            }
            // Which way the route goes (#258). A route that doubles back over the same road is
            // one ambiguous line without them. Annotations draw above both polylines, so they
            // stay readable over the track already ridden.
            RouteDirectionArrows(
                placements: arrows.placements,
                pointSize: arrows.pointSize,
                tint: .cyMapRoute,
                headingDegrees: arrowPose.headingDegrees,
                pitchDegrees: arrowPose.pitchDegrees
            )
        }
        .mapStyle(.standard(elevation: .realistic))
        // No default controls on either surface. The widget must have none, since a compass tap was
        // the way out of heading-up (#62); the sheet places its own column.
        .mapControls {}
        .onMapCameraChange(frequency: .onEnd) { context in
            camera = context.camera
            placeArrows(for: context)
            if pendingFollow != nil {
                completeSeed()
            } else if isSeedWanted {
                engage()
            }
        }
        // An arrow rotated for a heading two seconds old points somewhere the route does not go,
        // so the way up is taken every frame — but only that, and only to the degree, and only
        // while there is a route to draw arrows on. A following widget can also ride a long way
        // without the camera ever settling, so this is where that re-placement has to happen too.
        .onMapCameraChange(frequency: .continuous) { context in
            guard route.count > 1 else { return }
            let pose = ArrowPose(context.camera)
            if pose != arrowPose { arrowPose = pose }
            if LiveMapCamera.needsArrowRefresh(camera: context.camera, placedFor: arrowBounds) {
                placeArrows(for: context)
            }
        }
    }

    /// Where the arrows go for the camera `context` reports.
    ///
    /// The viewport comes from the camera rather than from `context.region`: the map is tilted
    /// while a route is loaded, and a pitched camera's region runs to the horizon — see
    /// `LiveMapCamera.visibleBounds(for:)`.
    private func placeArrows(for context: MapCameraUpdateContext) {
        guard route.count > 1,
              let bounds = LiveMapCamera.visibleBounds(for: context.camera)
        else {
            arrows = .none
            arrowBounds = nil
            return
        }
        arrowPose = ArrowPose(context.camera)
        arrowBounds = bounds
        arrows = RouteDirectionMarkers.arrows(
            coordinates: route,
            visibleBounds: bounds,
            // Drawn wider than they are counted, so the rider does not ride into an empty road
            // between re-placements, and so the tilt's extra ground is covered.
            drawingBounds: LiveMapCamera.arrowBounds(for: context.camera),
            limit: Self.arrowLimit
        )
    }

    /// The same cap as the route-browsing maps: the density rule is shared, so a route reads the
    /// same whether the rider is planning it or riding it.
    private static let arrowLimit = RouteDirectionMarkers.targetArrowsInView

    private var sheetControls: some View {
        VStack(spacing: Spacing.sm) {
            MapUserLocationButton(scope: mapScope)
            MapPitchToggle(scope: mapScope)
            MapCompass(scope: mapScope)
            MapOrientationButton(orientation: orientation, action: orientationTapped)
            if let overview = LiveMapCamera.overviewRegion(route: route) {
                RouteOverviewButton {
                    withAnimation { position = .region(overview) }
                }
            }
        }
        // MapKit's scoped controls take their shape from here. Without it the re-centre button draws as a
        // square (Apple's WWDC23 pattern for controls placed outside the map).
        .buttonBorderShape(.circle)
        .padding(Spacing.lg)
    }

    /// Tilts and turns the camera for `mode`, then follows the rider (see `LiveMapCamera`). With no
    /// camera reported yet there is nothing to seed from, so it follows now and seeds on the first report.
    private func engage() {
        guard let camera else {
            position = LiveMapCamera.follow(mode)
            isSeedWanted = LiveMapCamera.needsSeed(mode)
            return
        }
        isSeedWanted = false
        // Set before the seed is written, so the position change it causes is recognised as the seed.
        pendingFollow = LiveMapCamera.follow(mode)
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            position = .camera(LiveMapCamera.seed(from: camera, mode: mode))
        }
    }

    private func completeSeed() {
        guard let follow = pendingFollow else { return }
        pendingFollow = nil
        position = follow
    }

    private func orientationTapped() {
        switch LiveMapCamera.orientationTap(position: position, saved: orientation) {
        case .toggle:
            // The saved orientation changes, and `onChange(of: mode)` re-engages the camera.
            onOrientationToggle()
        case .reengage:
            engage()
        }
    }
}

// MARK: - Previews

private let previewTrack: [Coordinate] = [
    Coordinate(latitude: 43.0731, longitude: -89.4012),
    Coordinate(latitude: 43.0767, longitude: -89.4012)
]

private let previewRoute: [RouteCoordinate] = [
    RouteCoordinate(latitude: 43.0731, longitude: -89.4012, elevationMeters: nil),
    RouteCoordinate(latitude: 43.0803, longitude: -89.4012, elevationMeters: nil),
    RouteCoordinate(latitude: 43.0803, longitude: -89.3963, elevationMeters: nil)
]

#Preview("Sheet — route") {
    ActiveRideMapView(trackSegments: [previewTrack], route: previewRoute)
}

#Preview("Widget — no route") {
    ActiveRideMapView(trackSegments: [previewTrack], surface: .widget)
        .frame(height: 240)
}
