import MapKit
import SwiftUI

/// The direction-of-travel chevrons for a route, drawn where `RouteDirectionMarkers` put them.
///
/// Its own `MapContent` because three maps draw them and none of them should own a copy of the
/// glyph: S19 and S20 through `RouteMapContent`, and the live ride map directly (#258).
///
/// The live map is the reason `headingDegrees` and `pitchDegrees` exist. A chevron is an
/// `Annotation`, so its content is screen-space — MapKit neither turns it with the map nor lays
/// it flat in the map plane. On a heading-up, tilted navigation map an uncorrected chevron points
/// somewhere the route does not go, which is worse than no chevron at all. The correction itself
/// is arithmetic, and lives in `RouteDirectionMarkers.screenAngleDegrees` where tests can reach
/// it; both default to zero, which is a north-up flat map and leaves S19/S20 unchanged.
struct RouteDirectionChevrons: MapContent {
    let placements: [RouteDirectionMarkers.Placement]
    var tint: Color = .cyPrimary
    /// The map's heading, in degrees clockwise from true north.
    var headingDegrees: Double = 0
    /// The map's tilt, in degrees from straight down.
    var pitchDegrees: Double = 0

    @MapContentBuilder
    var body: some MapContent {
        ForEach(Array(placements.enumerated()), id: \.offset) { _, placement in
            Annotation("", coordinate: placement.coordinate.coordinate2D, anchor: .center) {
                Image(systemName: "chevron.up")
                    .font(.cyMapAnnotation)
                    .foregroundStyle(tint)
                    .rotationEffect(.degrees(RouteDirectionMarkers.screenAngleDegrees(
                        bearingDegrees: placement.bearingDegrees,
                        headingDegrees: headingDegrees,
                        pitchDegrees: pitchDegrees
                    )))
                    // Decorative: on S20 the flags carry start and finish for VoiceOver, and
                    // dozens of unlabelled rotated glyphs would only make the map harder to hear.
                    .accessibilityHidden(true)
            }
            .annotationTitles(.hidden)
        }
    }
}
