import CoreLocation
import MapKit
import SwiftUI

/// One route drawn on a map: its polyline, direction-of-travel chevrons, and flags at the ends.
///
/// A `MapContent` rather than a `View`, so both screens drop it straight into their own
/// `Map { }` — S19 inside a `ForEach` over every saved route, S20 (#195) once for the route
/// being viewed. UX.md §S20 asks for the start flag, the checkered finish flag and the
/// direction of travel; #194 puts the same treatment on S19 so a route reads the same way
/// wherever the rider meets it.
///
/// Everything that could be *wrong* — where the chevrons go, which way they point — lives in
/// `RouteDirectionMarkers` as pure arithmetic, because a live `Map` cannot be pixel-snapshot
/// tested reliably (`RoutesMapCamera.swift:6-9`). This type only draws what it is handed.
struct RouteMapContent: MapContent {
    let coordinates: [RouteCoordinate]
    /// S19 puts the route's name here, since that is how a rider tells eight polylines apart.
    /// S20 shows one route and says "Start".
    var startTitle: String = ""
    /// Empty on S19, where a second label per route is noise. "Finish" on S20.
    var finishTitle: String = ""
    var strokeWidth: CGFloat = 5
    /// The current viewport. Nil means no chevrons: spacing is derived from what is on screen,
    /// and guessing it from the route's own length would make one route read differently on
    /// two screens.
    var visibleBounds: RouteBounds?
    var chevronLimit: Int = 24

    /// Start and finish closer together than this is a loop, and a loop has no finish to mark.
    /// Without this every loop route stacks a checkered flag on top of its start flag, which
    /// reads as one smudged marker rather than as "you end where you began".
    static let loopClosureMeters = 25.0

    @MapContentBuilder
    var body: some MapContent {
        if coordinates.count > 1 {
            MapPolyline(coordinates: coordinates.map(\.coordinate2D))
                .stroke(Color.cyPrimary, lineWidth: strokeWidth)
        }

        ForEach(Array(chevrons.enumerated()), id: \.offset) { _, placement in
            Annotation("", coordinate: placement.coordinate.coordinate2D, anchor: .center) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.cyPrimary)
                    .rotationEffect(.degrees(placement.bearingDegrees))
                    // Decorative: the flags carry start and finish for VoiceOver, and dozens
                    // of unlabelled rotated glyphs would only make the map harder to hear.
                    .accessibilityHidden(true)
            }
            .annotationTitles(.hidden)
        }

        if let start = coordinates.first {
            Marker(startTitle, systemImage: "flag.fill", coordinate: start.coordinate2D)
                .tint(Color.cyPrimary)
        }

        if let finish = coordinates.last, !isLoop {
            // Checkered rather than tinted blue: UX.md §S20 asks for a blue checkered flag,
            // but there is no blue in `colors.md` that means "finish" — `info` means info
            // badges — and inventing a hex here would be exactly what the colour-token rule
            // forbids. The checkered pattern is what carries the meaning, so it is drawn in
            // the foreground token and reads against map tiles in both schemes.
            Marker(finishTitle, systemImage: "flag.checkered", coordinate: finish.coordinate2D)
                .tint(Color.cyTextPrimary)
        }
    }

    private var chevrons: [RouteDirectionMarkers.Placement] {
        RouteDirectionMarkers.placements(
            coordinates: coordinates,
            visibleBounds: visibleBounds,
            limit: chevronLimit
        )
    }

    private var isLoop: Bool {
        guard let start = coordinates.first, let finish = coordinates.last,
              coordinates.count > 1
        else { return false }
        return RouteGeometry.distanceMeters([start, finish]) < Self.loopClosureMeters
    }
}

/// The bridge lives in the UI layer, not on `RouteCoordinate`: the route models import
/// Foundation only, which is what keeps CoreLocation out of the layer doing the geometry
/// arithmetic. Moved here from `RoutesView`, where it was private, so S20 can reuse it.
extension RouteCoordinate {
    var coordinate2D: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
