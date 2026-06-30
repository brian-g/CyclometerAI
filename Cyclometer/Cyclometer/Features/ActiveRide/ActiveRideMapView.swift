import SwiftUI
import MapKit

/// Live ride map — follows the rider's location and heading (the map rotates so
/// the direction of travel points up) and draws the track travelled so far. The
/// native MapCompass shows where north is while the map rotates live; tapping it
/// reorients the map to north-up. Shared by the W8 map widget (rows 6–7) and the
/// full-screen map sheet. The map surface bleeds freely into the safe areas
/// (S05 — Map widget safe-area bleed); the compass control stays inside the
/// safe area bounds.
struct ActiveRideMapView: View {
    let coordinate: Coordinate?       // rider position; nil when GPS denied/unavailable
    let heading: Double               // degrees from true north; -1 = unavailable
    let coordinates: [Coordinate]     // recorded track travelled
    /// Reports the live map orientation back to the store: true while the map
    /// follows heading (heading-up), false once the compass reorients to north.
    var onHeadingUpChanged: (Bool) -> Void = { _ in }

    // The map owns its own camera so the native compass tap can reorient it to
    // north and have that stick. Starts heading-up (follows the direction of
    // travel); `.automatic` fallback keeps the map rendering when GPS is denied.
    @State private var position: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)

    var body: some View {
        Map(position: $position, interactionModes: [.rotate]) {
            // Custom position marker in brand green (brPrimary/cyPrimary) with a
            // heading indicator — replaces the default blue UserAnnotation. Shown
            // only when a fix is available, so a denied/no-fix map still renders.
            if let coordinate {
                Annotation("", coordinate: coordinate.clLocationCoordinate2D, anchor: .center) {
                    RiderMarker(heading: heading)
                }
                .annotationTitles(.hidden)
            }
            // Recorded track travelled — distinct from the planned-route polyline,
            // which arrives in M8.
            MapPolyline(coordinates: coordinates.map(\.clLocationCoordinate2D))
                .stroke(Color.cyPrimary, lineWidth: 5)
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls { MapCompass() }
        .mapControlVisibility(.visible)
        .onMapCameraChange(frequency: .onEnd) { context in
            // Heading-up while the camera is rotated to follow travel; north-up
            // once the native compass tap resets rotation to 0.
            onHeadingUpChanged(context.camera.heading != 0)
        }
    }
}

// MARK: - Rider Marker

/// Current-position marker: a brand-green dot with a white ring and a heading
/// arrow orbiting the dot. The arrow is hidden when heading is unavailable.
private struct RiderMarker: View {
    let heading: Double

    private static let markerSize: CGFloat = 44
    private static let dotSize: CGFloat = 18

    var body: some View {
        ZStack {
            if heading >= 0 {
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.cyPrimary)
                    .frame(width: Self.markerSize, height: Self.markerSize, alignment: .top)
                    .rotationEffect(.degrees(heading))
            }
            Circle()
                .fill(Color.cyPrimary)
                .frame(width: Self.dotSize, height: Self.dotSize)
                .overlay(Circle().stroke(.white, lineWidth: 3))
                .shadow(radius: 2)
        }
        .frame(width: Self.markerSize, height: Self.markerSize)
    }
}

#Preview {
    ActiveRideMapView(
        coordinate: Coordinate(latitude: 37.3349, longitude: -122.0090),
        heading: 45,
        coordinates: []
    )
}
