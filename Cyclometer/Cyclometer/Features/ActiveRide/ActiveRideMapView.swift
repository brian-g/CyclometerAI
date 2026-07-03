import SwiftUI
import MapKit

/// Live ride map — follows the rider's location and heading (the map rotates so
/// the direction of travel points up) and draws the track travelled so far. The
/// native MapCompass shows where north is while the map rotates live; tapping it
/// reorients the map to north-up. Used as the W8 widget preview (rows 6–7, no
/// gestures) and inside the full-screen map sheet (all gestures). The map
/// surface bleeds freely into the safe areas (S05 — Map widget safe-area bleed);
/// the map controls stay inside the safe area bounds.
struct ActiveRideMapView: View {
    let coordinates: [Coordinate]     // recorded track travelled
    /// Gesture support. The grid widget passes `[]` (tap opens the sheet); the
    /// full-screen sheet passes `.all` for pinch-zoom / pan / rotate.
    var interactionModes: MapInteractionModes = .all

    // Heading-up follow (MKUserTrackingMode.followWithHeading): the map rotates
    // so travel points up. `.automatic` fallback keeps the map rendering when
    // GPS is denied. The native MapUserLocationButton re-engages tracking after
    // the rider pans away.
    @State private var position: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)

    var body: some View {
        Map(position: $position, interactionModes: interactionModes) {
            // Standard Apple user-location marker (one marker, system colour).
            UserAnnotation()
            // Recorded track travelled — distinct from the planned-route polyline
            // (`mapRoute`), which arrives in M8.
            MapPolyline(coordinates: coordinates.map(\.clLocationCoordinate2D))
                .stroke(Color.cyMapTravelPath, lineWidth: 5)
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapCompass()
            // MapUserLocationButton manages the user-tracking mode and overrides
            // the heading-up follow camera (downgrading it to plain follow), so
            // it's shown only in the interactive sheet — never on the live grid
            // widget, which must stay heading-up. MapScaleView rides along there.
            if !interactionModes.isEmpty {
                MapUserLocationButton()
                MapScaleView()
            }
        }
        .mapControlVisibility(.visible)
    }
}

#Preview {
    ActiveRideMapView(coordinates: [])
}
