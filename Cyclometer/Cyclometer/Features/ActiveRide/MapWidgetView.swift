import SwiftUI
import MapKit

// MARK: - W8 Map Widget

/// W8 — Map 2×2. A live MapKit preview of the rider's position and track. The
/// preview itself is non-interactive (gestures disabled); tapping it opens a
/// large modal sheet — the only allowed way to open detail from a widget — where
/// the map supports full pinch-zoom / pan / rotate.
struct MapWidget: View {
    let coordinates: [Coordinate]
    var size: WidgetSize = .twoByTwo

    @State private var showMapSheet = false

    var body: some View {
        ActiveRideMapView(coordinates: coordinates, interactionModes: [])
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.cyBgSecondary)
            .contentShape(Rectangle())
            .onTapGesture { showMapSheet = true }
            .sheet(isPresented: $showMapSheet) {
                ActiveRideMapView(coordinates: coordinates, interactionModes: .all)
                    .ignoresSafeArea()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
    }
}

// MARK: - Previews

private let previewTrack: [Coordinate] = [
    Coordinate(latitude: 37.3318, longitude: -122.0312),
    Coordinate(latitude: 37.3330, longitude: -122.0205),
    Coordinate(latitude: 37.3349, longitude: -122.0090)
]

#Preview("2×2 — With Track") {
    MapWidget(coordinates: previewTrack)
        .frame(width: 393, height: 200)
}

#Preview("2×2 — No Track") {
    MapWidget(coordinates: [])
        .frame(width: 393, height: 200)
}
