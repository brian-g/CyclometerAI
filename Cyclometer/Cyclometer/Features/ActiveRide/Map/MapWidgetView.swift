import SwiftUI
import MapKit

// MARK: - W8 Map Widget

/// W8 — Map 2×2. A live MapKit preview of the rider's position, track and route. The preview is always
/// heading-up and non-interactive (#199, #62). Tapping it opens a large modal sheet, the only allowed
/// way to open detail from a widget, where the map supports full pinch-zoom / pan / rotate and opens
/// in the rider's saved orientation.
struct MapWidget: View {
    /// The recorded track, split into segments at every pause (#263).
    let trackSegments: [[Coordinate]]
    /// The route being ridden, drawn beneath the track. Empty on a free ride.
    var route: [RouteCoordinate] = []
    /// The sheet's saved orientation (#199). The widget itself is always heading-up.
    var sheetOrientation: MapOrientation = .headingUp
    var onOrientationToggle: () -> Void = {}
    var size: WidgetSize = .twoByTwo

    var body: some View {
        ActiveRideMapView(trackSegments: trackSegments, route: route, surface: .widget)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.cyBgSecondary)
            .widgetDetail(label: MapDashboardWidget.title) {
                LiveMapSheet(
                    trackSegments: trackSegments,
                    route: route,
                    orientation: sheetOrientation,
                    onOrientationToggle: onOrientationToggle
                )
            }
    }
}

/// The full-screen map sheet's content, detents included. Every widget whose tap opens the map — W8,
/// and W9, W19 and W20's "Sheet: Map" (#200, #461) — presents this through `.widgetDetail`, so they
/// show the same sheet.
struct LiveMapSheet: View {
    let trackSegments: [[Coordinate]]
    let route: [RouteCoordinate]
    let orientation: MapOrientation
    let onOrientationToggle: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // A bar only for the close every sheet carries (#335). It has no background, so the map
        // still runs to the sheet's top edge, and the map's controls sit below it.
        NavigationStack {
            ActiveRideMapView(
                trackSegments: trackSegments,
                route: route,
                surface: .sheet,
                orientation: orientation,
                onOrientationToggle: onOrientationToggle
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    /// An empty sheet: the `detail` default of a widget view drawn without a store — previews and
    /// snapshots, which never open it.
    static var placeholder: LiveMapSheet {
        LiveMapSheet(trackSegments: [[]], route: [], orientation: .headingUp, onOrientationToggle: {})
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

#Preview("Sheet") {
    Color.cyBgSecondary
        .sheet(isPresented: .constant(true)) {
            LiveMapSheet(trackSegments: [previewTrack], route: previewRoute, orientation: .headingUp, onOrientationToggle: {})
        }
}

#Preview("2×2 — With Track") {
    MapWidget(trackSegments: [previewTrack])
        .frame(width: 393, height: 200)
}

#Preview("2×2 — With Route") {
    MapWidget(trackSegments: [previewTrack], route: previewRoute)
        .frame(width: 393, height: 200)
}

#Preview("2×2 — No Track") {
    MapWidget(trackSegments: [[]])
        .frame(width: 393, height: 200)
}
