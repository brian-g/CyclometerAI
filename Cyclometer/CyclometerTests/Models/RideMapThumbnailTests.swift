import ComposableArchitecture
import CoreGraphics
import Foundation
import MapKit
import Testing
import UIKit
@testable import Cyclometer

/// #177: everything the thumbnail shows is decided here, without map tiles — tiles come over
/// the network and a live map can't be pixel-tested reliably, so the one MapKit step sits
/// behind `MapSnapshotClient` and is stubbed.
@Suite("RideMapThumbnail")
struct RideMapThumbnailTests {
    private static let rideId = UUID()

    private static func point(_ latitude: Double, _ longitude: Double, segment: Int = 0) -> TrackPointDTO {
        TrackPointDTO(
            rideId: rideId, timestamp: Date(timeIntervalSince1970: 0),
            latitude: latitude, longitude: longitude,
            altitudeMeters: 0, horizontalAccuracyMeters: 5,
            speedSource: .gps, heartRateSource: .none,
            segmentIndex: segment
        )
    }

    /// Two stretches of riding with a pause between them, and the resume point far enough
    /// from the pause point that a line across the gap would be obvious.
    private static let pausedRide = [
        point(43.070, -89.400), point(43.071, -89.401), point(43.072, -89.402),
        point(43.080, -89.390, segment: 1), point(43.081, -89.391, segment: 1),
    ]

    /// Every element of a path, as (is it a move, where it goes).
    private static func elements(of path: CGPath) -> [(isMove: Bool, point: CGPoint)] {
        var elements: [(isMove: Bool, point: CGPoint)] = []
        path.applyWithBlock { element in
            let type = element.pointee.type
            guard type == .moveToPoint || type == .addLineToPoint else { return }
            elements.append((type == .moveToPoint, element.pointee.points[0]))
        }
        return elements
    }

    /// Longitude → x, latitude → y. Not a map projection, just a function whose output the
    /// test can predict.
    private static func linear(_ coordinate: RouteCoordinate) -> CGPoint {
        CGPoint(x: coordinate.longitude, y: coordinate.latitude)
    }

    // MARK: - Segments

    @Test("the track splits at a pause, keeping each stretch's points in order")
    func splitsAtPause() {
        let segments = RideMapThumbnail.drawableSegments(Self.pausedRide)
        #expect(segments.count == 2)
        #expect(segments[0].map(\.latitude) == [43.070, 43.071, 43.072])
        #expect(segments[1].map(\.latitude) == [43.080, 43.081])
    }

    @Test("a stretch of a single point is dropped: it draws nothing")
    func dropsSinglePointStretch() {
        let track = Self.pausedRide + [Self.point(43.090, -89.380, segment: 2)]
        #expect(RideMapThumbnail.drawableSegments(track).count == 2)
    }

    @Test("a ride with no track, or a single fix, has nothing to draw")
    func nothingToDraw() {
        #expect(RideMapThumbnail.drawableSegments([]).isEmpty)
        #expect(RideMapThumbnail.drawableSegments([Self.point(43.07, -89.40)]).isEmpty)
    }

    // MARK: - Path

    @Test("the path starts a new subpath at the pause instead of drawing a line across it")
    func pathBreaksAtPause() {
        let segments = RideMapThumbnail.drawableSegments(Self.pausedRide)
        let elements = Self.elements(of: RideMapThumbnail.path(segments, project: Self.linear))

        #expect(elements.map(\.isMove) == [true, false, false, true, false])
        // Every point lands where the projection put it.
        #expect(elements.map(\.point) == segments.flatMap { $0 }.map(Self.linear))
    }

    // MARK: - Framing

    @Test("the region is centred on the whole track and contains all of it")
    func regionContainsTrack() {
        let segments = RideMapThumbnail.drawableSegments(Self.pausedRide)
        let region = RideMapThumbnail.region(for: segments)
        let coordinates = segments.flatMap { $0 }

        let minLatitude = coordinates.map(\.latitude).min()!, maxLatitude = coordinates.map(\.latitude).max()!
        let minLongitude = coordinates.map(\.longitude).min()!, maxLongitude = coordinates.map(\.longitude).max()!
        #expect(abs(region.center.latitude - (minLatitude + maxLatitude) / 2) < 1e-9)
        #expect(abs(region.center.longitude - (minLongitude + maxLongitude) / 2) < 1e-9)
        #expect(region.span.latitudeDelta >= maxLatitude - minLatitude)
        #expect(region.span.longitudeDelta >= maxLongitude - minLongitude)
    }

    // MARK: - Capture

    @Test("capture renders both appearances from the persisted track and stores them on the ride")
    func captureStoresBothAppearances() async throws {
        let rendered = LockIsolated<[UIUserInterfaceStyle]>([])
        let saved = LockIsolated<[(UUID, Data, Data)]>([])

        try await withDependencies {
            $0.persistenceClient = .mock(
                trackPoints: [Self.rideId: Self.pausedRide],
                onSaveRideMapThumbnail: { id, light, dark in saved.withValue { $0.append((id, light, dark)) } }
            )
            $0.mapSnapshotClient = MapSnapshotClient { _, segments, style in
                #expect(segments == RideMapThumbnail.drawableSegments(Self.pausedRide))
                rendered.withValue { $0.append(style) }
                return Data(style == .dark ? "dark".utf8 : "light".utf8)
            }
        } operation: {
            try await RideMapThumbnail.capture(rideId: Self.rideId)
        }

        #expect(Set(rendered.value) == [.light, .dark])
        #expect(saved.value.count == 1)
        let (id, light, dark) = try #require(saved.value.first)
        #expect(id == Self.rideId)
        #expect(light == Data("light".utf8))
        #expect(dark == Data("dark".utf8))
    }

    @Test("capture of a ride with nothing to draw renders nothing and stores nothing")
    func captureSkipsEmptyTrack() async throws {
        let renderCount = LockIsolated(0)
        let saveCount = LockIsolated(0)

        try await withDependencies {
            $0.persistenceClient = .mock(
                trackPoints: [Self.rideId: [Self.point(43.07, -89.40)]],
                onSaveRideMapThumbnail: { _, _, _ in saveCount.withValue { $0 += 1 } }
            )
            $0.mapSnapshotClient = MapSnapshotClient { _, _, _ in
                renderCount.withValue { $0 += 1 }
                return Data()
            }
        } operation: {
            try await RideMapThumbnail.capture(rideId: Self.rideId)
        }

        #expect(renderCount.value == 0)
        #expect(saveCount.value == 0)
    }

    @Test("a failed render stores nothing and surfaces the error to the caller")
    func captureRenderFailureStoresNothing() async throws {
        let saveCount = LockIsolated(0)

        await #expect(throws: MapSnapshotError.unavailable) {
            try await withDependencies {
                $0.persistenceClient = .mock(
                    trackPoints: [Self.rideId: Self.pausedRide],
                    onSaveRideMapThumbnail: { _, _, _ in saveCount.withValue { $0 += 1 } }
                )
                $0.mapSnapshotClient = .testValue
            } operation: {
                try await RideMapThumbnail.capture(rideId: Self.rideId)
            }
        }
        #expect(saveCount.value == 0)
    }
}
