import SwiftUI
import MapKit

// MARK: - W8 Map Widget

/// W8 — Map 2×2. A live MapKit preview of the rider's position, track and route. The preview is always
/// heading-up and non-interactive (#199, #62). Tapping it opens a large modal sheet, the only allowed
/// way to open detail from a widget, where the map supports full pinch-zoom / pan / rotate and opens
/// in the rider's saved orientation.
struct MapWidget: View {
    let coordinates: [Coordinate]
    /// The route being ridden, drawn beneath the track. Empty on a free ride.
    var route: [RouteCoordinate] = []
    /// The sheet's saved orientation (#199). The widget itself is always heading-up.
    var sheetOrientation: MapOrientation = .headingUp
    var onOrientationToggle: () -> Void = {}
    var size: WidgetSize = .twoByTwo

    @State private var showMapSheet = false

    var body: some View {
        ActiveRideMapView(coordinates: coordinates, route: route, surface: .widget)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.cyBgSecondary)
            .contentShape(Rectangle())
            .onTapGesture { showMapSheet = true }
            .liveMapSheet(
                isPresented: $showMapSheet,
                coordinates: coordinates,
                route: route,
                orientation: sheetOrientation,
                onOrientationToggle: onOrientationToggle
            )
    }
}

extension View {
    /// The full-screen map sheet. Shared by every widget whose tap opens the map — W8, and W9's
    /// "Sheet: Map" (#200) — so they cannot present it differently.
    func liveMapSheet(
        isPresented: Binding<Bool>,
        coordinates: [Coordinate],
        route: [RouteCoordinate],
        orientation: MapOrientation,
        onOrientationToggle: @escaping () -> Void
    ) -> some View {
        sheet(isPresented: isPresented) {
            ActiveRideMapView(
                coordinates: coordinates,
                route: route,
                surface: .sheet,
                orientation: orientation,
                onOrientationToggle: onOrientationToggle
            )
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

private let previewRoute: [RouteCoordinate] = [
    RouteCoordinate(latitude: 37.3318, longitude: -122.0312, elevationMeters: nil),
    RouteCoordinate(latitude: 37.3349, longitude: -122.0090, elevationMeters: nil),
    RouteCoordinate(latitude: 37.3400, longitude: -121.9990, elevationMeters: nil)
]

#Preview("2×2 — With Track") {
    MapWidget(coordinates: previewTrack)
        .frame(width: 393, height: 200)
}

#Preview("2×2 — With Route") {
    MapWidget(coordinates: previewTrack, route: previewRoute)
        .frame(width: 393, height: 200)
}

#Preview("2×2 — No Track") {
    MapWidget(coordinates: [])
        .frame(width: 393, height: 200)
}
