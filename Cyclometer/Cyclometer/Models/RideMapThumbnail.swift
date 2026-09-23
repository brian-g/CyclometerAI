import ComposableArchitecture
import CoreGraphics
import Foundation
import MapKit

/// S14's row thumbnail (#177): the ride's recorded track over a static map, rendered once at
/// ride end so the list never stands up a live `Map` per row (UX.md §S14).
///
/// Everything that decides what the image shows — which points are drawn, how the map is
/// framed, where the line lands — is plain arithmetic here. The one step that needs map tiles
/// sits behind `MapSnapshotClient`, because tiles arrive over the network and cannot be
/// pixel-tested reliably (`RoutesMapCamera.swift:6-9`).
enum RideMapThumbnail {
    /// UX.md §S14: a 56×56pt square.
    static let pointSize = CGSize(width: Spacing.rideThumbnail, height: Spacing.rideThumbnail)
    /// #51: sized for an @3x iPhone display.
    static let scale: CGFloat = 3

    /// The track as polylines, one per stretch of riding, split at every pause (#263) so no
    /// line is drawn across one. A stretch of fewer than two points draws nothing and is
    /// dropped, so an empty result means the ride has no track to show — a trainer ride, or
    /// one that never got a GPS fix.
    static func drawableSegments(_ trackPoints: [TrackPointDTO]) -> [[RouteCoordinate]] {
        TrackPointDTO.segments(of: trackPoints)
            .filter { $0.count > 1 }
            .map { $0.map { RouteCoordinate(latitude: $0.latitude, longitude: $0.longitude) } }
    }

    /// Framed the way the app fits every other map around its content, padding and minimum
    /// span included. The snapshotter widens whichever axis the square needs, about the centre.
    static func region(for segments: [[RouteCoordinate]]) -> MKCoordinateRegion {
        RoutesMapCamera.region(fitting: RouteGeometry.boundingBox(segments.flatMap { $0 }))
    }

    /// The track in image space, one subpath per segment. In the app `project` is the
    /// snapshot's own `point(for:)`, the only projection guaranteed to agree with the tiles
    /// underneath; in tests it is any plain function.
    static func path(_ segments: [[RouteCoordinate]], project: (RouteCoordinate) -> CGPoint) -> CGPath {
        let path = CGMutablePath()
        for segment in segments {
            guard let first = segment.first else { continue }
            path.move(to: project(first))
            for coordinate in segment.dropFirst() {
                path.addLine(to: project(coordinate))
            }
        }
        return path
    }

    /// Renders both appearances from the ride's persisted track and stores them on the ride.
    /// A ride with no drawable track is left without one, which is not an error.
    ///
    /// Reads the track back from persistence, like `GPXExporter.generate`, so it has to run
    /// after the ride-end flush. Dependencies are resolved here rather than held in `static`
    /// properties for the reason given on `GPXExporter.generate` (#242).
    static func capture(rideId: UUID) async throws {
        @Dependency(\.persistenceClient) var persistenceClient
        @Dependency(\.mapSnapshotClient) var mapSnapshotClient
        let segments = drawableSegments(try await persistenceClient.fetchTrackPoints(rideId))
        guard !segments.isEmpty else { return }
        let region = region(for: segments)
        async let light = mapSnapshotClient.render(region, segments, .light)
        async let dark = mapSnapshotClient.render(region, segments, .dark)
        try await persistenceClient.saveRideMapThumbnail(rideId, light, dark)
    }
}
