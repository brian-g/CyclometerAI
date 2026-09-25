import ComposableArchitecture
import CoreGraphics
import Foundation
import MapKit
import os

// Stream live: Console.app / Xcode console, filter subsystem "com.xavier.cyclometer".
private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "recording")

/// S14's row thumbnail (#177): the ride's recorded track over a static map, rendered once
/// after the ride ends so the list never stands up a live `Map` per row (UX.md §S14).
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

    /// A ride that barely moved is shown at least this wide, so GPS jitter reads as a dot
    /// rather than a scribble at street level.
    static let minimumSideMeters: CLLocationDistance = 200

    /// From the centre of the track's stroke to the image edge: the margin, plus half the stroke.
    static let inset = Spacing.mapThumbnailMargin + Spacing.strokeMapThumbnail / 2

    /// A square framed so the track fills the image, `Spacing.mapThumbnailMargin` from its edge
    /// on the longer axis (#280). Unlike the other maps, which pad and floor a region in degrees
    /// (`RoutesMapCamera.region(fitting:)`), a thumbnail is too small to spare that padding.
    ///
    /// In map points, the snapshotter's own projection. A square rect in a square image scales
    /// uniformly, so a margin in points is the same fraction of the rect.
    static func mapRect(for segments: [[RouteCoordinate]]) -> MKMapRect {
        let bounds = RouteGeometry.boundingBox(segments.flatMap { $0 })
        // Mercator keeps north up and east right, so the box's corners bound the projected track.
        let topLeft = MKMapPoint(CLLocationCoordinate2D(latitude: bounds.maxLatitude, longitude: bounds.minLongitude))
        let bottomRight = MKMapPoint(CLLocationCoordinate2D(latitude: bounds.minLatitude, longitude: bounds.maxLongitude))
        let track = MKMapRect(x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y)

        let latitude = (bounds.minLatitude + bounds.maxLatitude) / 2
        let minimumSide = minimumSideMeters * MKMapPointsPerMeterAtLatitude(latitude)
        let contentSide = max(track.width, track.height, minimumSide)
        // Kept inside the world: a track across ±180°, which `RouteBounds` leaves unhandled, spans
        // nearly all of it, and MapKit answers a rect outside the world with an arbitrary camera
        // (`RoutesMapCamera.span(_:limit:)` guards the same).
        let world = MKMapRect.world
        let side = min(contentSide * pointSize.width / (pointSize.width - 2 * inset), world.width, world.height)
        return MKMapRect(
            x: min(max(track.midX - side / 2, world.minX), world.maxX - side),
            y: min(max(track.midY - side / 2, world.minY), world.maxY - side),
            width: side, height: side
        )
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

    /// Renders the thumbnail of every finished ride that lacks one, newest first, and returns
    /// how many it stored.
    ///
    /// The one way thumbnails get made, whichever way a ride ended. It runs right after a
    /// Finish, where the newest ride is the one just finished. It runs again at launch, which
    /// catches rides AppFeature closed out and any earlier capture that failed. Offline at the
    /// trailhead, or suspended mid-render, is then a thumbnail late rather than never.
    ///
    /// A ride with nothing to draw is skipped and looked at again next time, which is one
    /// empty track fetch. The first failed render ends the batch: offline, every ride would
    /// fail the same way, each one waiting on the network first.
    ///
    /// One at a time (#248 review): a Finish can land while the launch backfill still waits on
    /// the network, and both would render and save the same rides. The later one waits, then
    /// reads the missing list afresh, so it only does what the first one didn't.
    @discardableResult
    static func backfill() async -> Int {
        @Dependency(\.mapThumbnailGate) var gate
        return await gate.run { await backfillNow() }
    }

    private static func backfillNow() async -> Int {
        @Dependency(\.persistenceClient) var persistenceClient
        let rideIds: [UUID]
        do {
            rideIds = try await persistenceClient.fetchRideIdsMissingMapThumbnail()
        } catch {
            return 0 // Logged inside RidePersistenceActor.
        }
        var stored = 0
        for rideId in rideIds {
            do {
                if try await capture(rideId: rideId) { stored += 1 }
            } catch {
                logger.error("Map thumbnail capture failed for \(rideId, privacy: .public): \(error.localizedDescription, privacy: .public) — retried next launch")
                break
            }
        }
        return stored
    }

    /// Renders both appearances from one ride's persisted track and stores them on the ride.
    /// Returns false, having stored nothing, for a ride with no drawable track.
    ///
    /// Reads the track back from persistence, like `GPXExporter.fetchInputs`, so it has to run
    /// after the ride-end flush. Dependencies are resolved here rather than held in `static`
    /// properties for the reason given on `GPXExporter.fetchInputs` (#242).
    @discardableResult
    static func capture(rideId: UUID) async throws -> Bool {
        @Dependency(\.persistenceClient) var persistenceClient
        @Dependency(\.mapSnapshotClient) var mapSnapshotClient
        let segments = drawableSegments(try await persistenceClient.fetchTrackPoints(rideId))
        guard !segments.isEmpty else { return false }
        let mapRect = mapRect(for: segments)
        async let light = mapSnapshotClient.render(mapRect, segments, .cyMapTravelPath, .light)
        async let dark = mapSnapshotClient.render(mapRect, segments, .cyMapTravelPath, .dark)
        try await persistenceClient.saveRideMapThumbnail(rideId, light, dark)
        return true
    }
}

/// Lets one `RideMapThumbnail.backfill` run at a time; later callers queue in order (#248
/// review). A dependency rather than a `static` so tests running in parallel each get their
/// own and never wait on one another's renders.
actor MapThumbnailGate {
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run<T: Sendable>(_ operation: @Sendable () async -> T) async -> T {
        if isBusy {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            isBusy = true
        }
        // Handed straight to the next waiter, so the gate never reads free while one waits.
        defer {
            if waiters.isEmpty { isBusy = false } else { waiters.removeFirst().resume() }
        }
        return await operation()
    }
}

extension MapThumbnailGate: DependencyKey {
    static let liveValue = MapThumbnailGate()
    static var testValue: MapThumbnailGate { MapThumbnailGate() }
}

extension DependencyValues {
    var mapThumbnailGate: MapThumbnailGate {
        get { self[MapThumbnailGate.self] }
        set { self[MapThumbnailGate.self] = newValue }
    }
}
