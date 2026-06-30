import SwiftUI

// MARK: - W8 Map Widget

/// W8 — Map 2×2. A live MapKit view of the rider's position and heading. Tapping
/// the map surface opens a full-screen map; the native compass control (inside
/// `ActiveRideMapView`) shows north and reorients to north-up when tapped. The
/// map surface bleeds into the safe area when placed in the first/last grid row,
/// while the compass control stays inside safe bounds.
struct MapWidget: View {
    let coordinate: Coordinate?
    let heading: Double
    let coordinates: [Coordinate]
    let isLocationAvailable: Bool
    var onHeadingUpChanged: (Bool) -> Void = { _ in }
    var size: WidgetSize = .twoByTwo

    @State private var showFullScreen = false

    var body: some View {
        map
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.cyBgSecondary)
            .contentShape(Rectangle())
            .onTapGesture { showFullScreen = true }
            .fullScreenCover(isPresented: $showFullScreen) { fullScreenMap }
    }

    private var map: some View {
        ActiveRideMapView(
            coordinate: coordinate,
            heading: heading,
            coordinates: coordinates,
            onHeadingUpChanged: onHeadingUpChanged
        )
    }

    // Full-screen map sheet (S05 "Sheet: Full-screen map"). Reuses the live map
    // with a dismiss control; the compass toggle comes along from the map view.
    private var fullScreenMap: some View {
        map
            .ignoresSafeArea()
            .overlay(alignment: .topLeading) {
                Button { showFullScreen = false } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .frame(width: Spacing.tapTarget, height: Spacing.tapTarget)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Close map")
                .padding(Spacing.md)
            }
    }
}

// MARK: - Previews

private let previewTrack: [Coordinate] = [
    Coordinate(latitude: 37.3318, longitude: -122.0312),
    Coordinate(latitude: 37.3330, longitude: -122.0205),
    Coordinate(latitude: 37.3349, longitude: -122.0090)
]

#Preview("2×2 — Active") {
    MapWidget(
        coordinate: Coordinate(latitude: 37.3349, longitude: -122.0090),
        heading: 45,
        coordinates: previewTrack,
        isLocationAvailable: true
    )
    .frame(width: 393, height: 200)
}

#Preview("2×2 — Location Denied") {
    MapWidget(
        coordinate: nil,
        heading: -1,
        coordinates: [],
        isLocationAvailable: false
    )
    .frame(width: 393, height: 200)
}
