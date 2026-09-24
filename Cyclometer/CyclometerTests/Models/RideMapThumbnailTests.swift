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

    /// Where a coordinate lands in the 56pt image of `mapRect`: the square rect maps linearly
    /// onto the square image.
    private static func imagePoint(_ coordinate: RouteCoordinate, in mapRect: MKMapRect) -> CGPoint {
        let point = MKMapPoint(coordinate.coordinate2D)
        let side = RideMapThumbnail.pointSize.width
        return CGPoint(
            x: (point.x - mapRect.minX) / mapRect.width * side,
            y: (point.y - mapRect.minY) / mapRect.height * side
        )
    }

    /// The track's extent in image points.
    private static func imageBounds(_ segments: [[RouteCoordinate]], in mapRect: MKMapRect) -> CGRect {
        let points = segments.joined().map { imagePoint($0, in: mapRect) }
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    /// About 0.4 mi out and back at 43°N — the ride #280 showed as a blob. The return leg sits
    /// a little to one side, so the short axis isn't zero.
    private static let eastWestRide = [[
        RouteCoordinate(latitude: 43.0700, longitude: -89.4000),
        RouteCoordinate(latitude: 43.0700, longitude: -89.3960),
        RouteCoordinate(latitude: 43.0703, longitude: -89.3960),
        RouteCoordinate(latitude: 43.0703, longitude: -89.4000),
    ]]
    private static let northSouthRide = [[
        RouteCoordinate(latitude: 43.0700, longitude: -89.4000),
        RouteCoordinate(latitude: 43.0729, longitude: -89.4000),
        RouteCoordinate(latitude: 43.0729, longitude: -89.4004),
        RouteCoordinate(latitude: 43.0700, longitude: -89.4004),
    ]]

    @Test("the frame is square and centred on the track")
    func mapRectIsSquareAndCentred() {
        for ride in [Self.eastWestRide, Self.northSouthRide, RideMapThumbnail.drawableSegments(Self.pausedRide)] {
            let mapRect = RideMapThumbnail.mapRect(for: ride)
            let bounds = Self.imageBounds(ride, in: mapRect)
            let side = RideMapThumbnail.pointSize.width
            #expect(abs(mapRect.width - mapRect.height) < 1e-6)
            #expect(abs(bounds.midX - side / 2) < 1e-6)
            #expect(abs(bounds.midY - side / 2) < 1e-6)
        }
    }

    @Test("a short ride fills the image on its longer axis, the stroke a margin in from the edge")
    func shortRideFillsLongAxis() {
        let side = RideMapThumbnail.pointSize.width
        let inset = RideMapThumbnail.inset

        let eastWest = Self.imageBounds(Self.eastWestRide, in: RideMapThumbnail.mapRect(for: Self.eastWestRide))
        #expect(abs(eastWest.minX - inset) < 1e-6)
        #expect(abs(eastWest.maxX - (side - inset)) < 1e-6)
        #expect(eastWest.minY > inset && eastWest.maxY < side - inset)

        let northSouth = Self.imageBounds(Self.northSouthRide, in: RideMapThumbnail.mapRect(for: Self.northSouthRide))
        #expect(abs(northSouth.minY - inset) < 1e-6)
        #expect(abs(northSouth.maxY - (side - inset)) < 1e-6)
        #expect(northSouth.minX > inset && northSouth.maxX < side - inset)
    }

    @Test("a ride that barely moved is framed at the minimum width, not zoomed to its GPS jitter")
    func stationaryRideIsFloored() {
        let jitter = [[
            RouteCoordinate(latitude: 43.07000, longitude: -89.40000),
            RouteCoordinate(latitude: 43.07003, longitude: -89.40002),
            RouteCoordinate(latitude: 43.06998, longitude: -89.40004),
        ]]
        let mapRect = RideMapThumbnail.mapRect(for: jitter)
        let side = RideMapThumbnail.pointSize.width
        let contentPoints = mapRect.width * (side - 2 * RideMapThumbnail.inset) / side
        let contentMeters = contentPoints / MKMapPointsPerMeterAtLatitude(43.07)
        #expect(abs(contentMeters - RideMapThumbnail.minimumSideMeters) < 0.01)

        let bounds = Self.imageBounds(jitter, in: mapRect)
        #expect(abs(bounds.midX - side / 2) < 1e-6)
        #expect(abs(bounds.midY - side / 2) < 1e-6)
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

    // MARK: - Backfill

    @Test("backfill captures every ride missing a thumbnail in the order given, skipping one with nothing to draw")
    func backfillCapturesMissingRides() async {
        let newest = UUID(), trainer = UUID(), oldest = UUID()
        let saved = LockIsolated<[UUID]>([])

        let stored = await withDependencies {
            $0.persistenceClient = .mock(
                trackPoints: [newest: Self.pausedRide, oldest: Self.pausedRide],
                rideIdsMissingMapThumbnail: [newest, trainer, oldest],
                onSaveRideMapThumbnail: { id, _, _ in saved.withValue { $0.append(id) } }
            )
            $0.mapSnapshotClient = MapSnapshotClient { _, _, _ in Data([1]) }
        } operation: {
            await RideMapThumbnail.backfill()
        }

        // The trainer ride has no track: skipped, not a failure, so the batch goes on.
        #expect(saved.value == [newest, oldest])
        #expect(stored == 2)
    }

    @Test("backfill stops at the first failed render: offline, every ride would fail the same way")
    func backfillStopsAtFirstFailure() async {
        let first = UUID(), second = UUID()
        let renders = LockIsolated(0)

        let stored = await withDependencies {
            $0.persistenceClient = .mock(
                trackPoints: [first: Self.pausedRide, second: Self.pausedRide],
                rideIdsMissingMapThumbnail: [first, second]
            )
            $0.mapSnapshotClient = MapSnapshotClient { _, _, _ in
                renders.withValue { $0 += 1 }
                throw MapSnapshotError.unavailable
            }
        } operation: {
            await RideMapThumbnail.backfill()
        }

        #expect(stored == 0)
        // Light and dark for the first ride at most; the second ride is never tried.
        #expect(renders.value <= 2)
    }

    /// #248 review: a Finish's capture landing while the launch backfill still renders must
    /// not render and save the same ride a second time.
    @Test("an overlapping backfill waits for the one running, then finds nothing left to do")
    func overlappingBackfillsRunOneAtATime() async {
        let saves = LockIsolated(0)
        let reads = LockIsolated(0)
        let renders = LockIsolated(0)
        let missing = LockIsolated([Self.rideId])
        let (renderStarted, renderStartedContinuation) = AsyncStream<Void>.makeStream()
        let (release, releaseContinuation) = AsyncStream<Void>.makeStream()

        await withDependencies {
            var client = PersistenceClient.mock(trackPoints: [Self.rideId: Self.pausedRide])
            client.fetchRideIdsMissingMapThumbnail = {
                reads.withValue { $0 += 1 }
                return missing.value
            }
            client.saveRideMapThumbnail = { _, _, _ in
                saves.withValue { $0 += 1 }
                missing.setValue([])
            }
            $0.persistenceClient = client
            // Only the very first render holds, until the second backfill has had its chance.
            $0.mapSnapshotClient = MapSnapshotClient { _, _, _ in
                if renders.withValue({ $0 += 1; return $0 }) == 1 {
                    renderStartedContinuation.yield()
                    for await _ in release { break }
                }
                return Data([1])
            }
        } operation: {
            async let first = RideMapThumbnail.backfill()
            for await _ in renderStarted { break }
            async let second = RideMapThumbnail.backfill()
            // Real time, not yields: the second call runs on its own task. Unguarded, it reads
            // the missing list within microseconds; one at a time, it can't until the first
            // is done. A loaded machine can only make this pass wrongly, never fail wrongly.
            try? await Task.sleep(for: .milliseconds(200))
            #expect(reads.value == 1, "the second backfill started while the first was rendering")
            releaseContinuation.yield()
            let stored = await (first, second)
            #expect(stored.0 == 1)
            #expect(stored.1 == 0)
        }
        #expect(saves.value == 1)
    }
}
