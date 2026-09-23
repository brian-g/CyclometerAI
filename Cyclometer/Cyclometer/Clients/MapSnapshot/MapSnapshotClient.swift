import ComposableArchitecture
import MapKit
import UIKit

/// TCA dependency for rendering a static map image — the one part of `RideMapThumbnail`
/// that needs MapKit's tiles, and so the part kept out of the test suite (#177).
struct MapSnapshotClient: Sendable {
    /// A PNG of `segments` stroked over a static map of `region`, at `RideMapThumbnail`'s
    /// size and scale, rendered for one appearance.
    var render: @Sendable (MKCoordinateRegion, [[RouteCoordinate]], UIUserInterfaceStyle) async throws -> Data
}

enum MapSnapshotError: Error, Equatable {
    case encodingFailed
    /// The inert test and preview value's answer: nothing was rendered.
    case unavailable
}

extension MapSnapshotClient: DependencyKey {
    static let liveValue = MapSnapshotClient { region, segments, style in
        // The base map is rendered for these traits and cannot adapt afterwards, which is why
        // a ride stores one image per appearance.
        let traits = UITraitCollection { traits in
            traits.displayScale = RideMapThumbnail.scale
            traits.userInterfaceStyle = style
        }
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = RideMapThumbnail.pointSize
        options.traitCollection = traits
        options.preferredConfiguration = thumbnailConfiguration()
        let snapshot = try await MKMapSnapshotter(options: options).start()
        return try draw(segments, over: snapshot, traits: traits)
    }

    static let testValue = MapSnapshotClient { _, _, _ in throw MapSnapshotError.unavailable }
    static let previewValue = testValue

    /// Muted, with every point of interest hidden — #51 asks for as few labels as possible.
    /// Place and road names have no public switch in a standard configuration, so those
    /// that MapKit shows at this zoom remain.
    private static func thumbnailConfiguration() -> MKStandardMapConfiguration {
        let configuration = MKStandardMapConfiguration(emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        return configuration
    }

    /// MapKit draws no overlays into a snapshot, so the track is stroked on top of it here,
    /// placed by the snapshot's own projection.
    private static func draw(
        _ segments: [[RouteCoordinate]],
        over snapshot: MKMapSnapshotter.Snapshot,
        traits: UITraitCollection
    ) throws -> Data {
        // Scale comes from the traits' displayScale, so snapshot and canvas cannot disagree.
        let format = UIGraphicsImageRendererFormat(for: traits)
        let image = UIGraphicsImageRenderer(size: RideMapThumbnail.pointSize, format: format).image { context in
            snapshot.image.draw(at: .zero)
            let cgContext = context.cgContext
            cgContext.addPath(RideMapThumbnail.path(segments) { snapshot.point(for: $0.coordinate2D) })
            // Resolved against the snapshot's own traits: the dark image needs the dark token,
            // whatever appearance the app happens to be in while this runs.
            cgContext.setStrokeColor(UIColor(resource: .cyMapTravelPath).resolvedColor(with: traits).cgColor)
            cgContext.setLineWidth(Spacing.strokeMapThumbnail)
            cgContext.setLineCap(.round)
            cgContext.setLineJoin(.round)
            cgContext.strokePath()
        }
        guard let data = image.pngData() else { throw MapSnapshotError.encodingFailed }
        return data
    }
}

extension DependencyValues {
    var mapSnapshotClient: MapSnapshotClient {
        get { self[MapSnapshotClient.self] }
        set { self[MapSnapshotClient.self] = newValue }
    }
}
