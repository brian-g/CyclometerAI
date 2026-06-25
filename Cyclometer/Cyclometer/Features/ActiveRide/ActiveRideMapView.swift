import SwiftUI
import MapKit

/// Live ride map — follows the rider's location and heading (the map rotates so
/// the direction of travel points up) and draws the track travelled so far.
/// Shared by the W8 map widget (rows 6–7) and the full-bleed page-2 map. The
/// map surface bleeds freely into the safe areas (S05 — Map widget safe-area
/// bleed); the compass control stays inside the safe area bounds.
struct ActiveRideMapView: View {
    let coordinates: [Coordinate]
    @State private var position: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)

    var body: some View {
        Map(position: $position, interactionModes: []) {
            UserAnnotation()
            MapPolyline(coordinates: coordinates.map(\.clLocationCoordinate2D))
                .stroke(Color.cyPrimary, lineWidth: 5)
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapCompass()
        }
        .mapControlVisibility(.visible)
    }
}

#Preview {
    ActiveRideMapView(coordinates: [])
}
