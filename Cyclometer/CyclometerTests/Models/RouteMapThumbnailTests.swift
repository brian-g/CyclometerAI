import ComposableArchitecture
import Foundation
import MapKit
import Testing
import UIKit
@testable import Cyclometer

/// S19's route-row thumbnail (#273). Framing and path are `RideMapThumbnail`'s and tested there;
/// this covers what a route does differently — where the line comes from, its colour, and where
/// the images go. No MapKit tiles: `MapSnapshotClient` is scripted throughout.
@Suite("RouteMapThumbnail")
struct RouteMapThumbnailTests {

    private static let path = [
        RouteCoordinate(latitude: 43.070, longitude: -89.400),
        RouteCoordinate(latitude: 43.075, longitude: -89.390),
        RouteCoordinate(latitude: 43.080, longitude: -89.385),
    ]

    private static func detail(_ id: UUID, _ coordinates: [RouteCoordinate] = path) -> RouteDetail {
        var summary = RouteSummary.empty
        summary.id = id
        return RouteDetail(summary: summary, coordinates: coordinates, cuePoints: [])
    }

    @Test("a route is one segment; fewer than two points draw nothing")
    func drawableSegments() {
        #expect(RouteMapThumbnail.drawableSegments(Self.path) == [Self.path])
        #expect(RouteMapThumbnail.drawableSegments([Self.path[0]]).isEmpty)
        #expect(RouteMapThumbnail.drawableSegments([]).isEmpty)
    }

    @Test("capture renders both appearances in the planned-route colour and stores them on the route")
    func captureStoresBothAppearances() async throws {
        let routeId = UUID()
        let rendered = LockIsolated<[UIUserInterfaceStyle]>([])
        let saved = LockIsolated<[(UUID, Data, Data)]>([])

        let stored = try await withDependencies {
            $0.persistenceClient = .mock(
                routeDetails: [routeId: Self.detail(routeId)],
                onSaveRouteMapThumbnail: { id, light, dark in saved.withValue { $0.append((id, light, dark)) } }
            )
            $0.mapSnapshotClient = MapSnapshotClient { mapRect, segments, stroke, style in
                #expect(segments == [Self.path])
                #expect(MKMapRectEqualToRect(mapRect, RideMapThumbnail.mapRect(for: segments)))
                #expect(stroke == .cyMapRoute)
                rendered.withValue { $0.append(style) }
                return Data(style == .dark ? "dark".utf8 : "light".utf8)
            }
        } operation: {
            try await RouteMapThumbnail.capture(routeId: routeId)
        }

        #expect(stored)
        #expect(Set(rendered.value) == [.light, .dark])
        let (id, light, dark) = try #require(saved.value.first)
        #expect(saved.value.count == 1)
        #expect(id == routeId)
        #expect(light == Data("light".utf8))
        #expect(dark == Data("dark".utf8))
    }

    @Test("capture of a route with nothing to draw, or one that is gone, renders and stores nothing")
    func captureSkipsUndrawableRoutes() async throws {
        let single = UUID(), gone = UUID()
        let renders = LockIsolated(0)
        let saves = LockIsolated(0)

        let (singleStored, goneStored) = try await withDependencies {
            $0.persistenceClient = .mock(
                routeDetails: [single: Self.detail(single, [Self.path[0]])],
                onSaveRouteMapThumbnail: { _, _, _ in saves.withValue { $0 += 1 } }
            )
            $0.mapSnapshotClient = MapSnapshotClient { _, _, _, _ in
                renders.withValue { $0 += 1 }
                return Data()
            }
        } operation: {
            (try await RouteMapThumbnail.capture(routeId: single), try await RouteMapThumbnail.capture(routeId: gone))
        }

        #expect(!singleStored)
        #expect(!goneStored)
        #expect(renders.value == 0)
        #expect(saves.value == 0)
    }

    @Test("backfill captures every route missing a thumbnail in the order given, skipping one with nothing to draw")
    func backfillCapturesMissingRoutes() async {
        let newest = UUID(), single = UUID(), oldest = UUID()
        let saved = LockIsolated<[UUID]>([])

        let stored = await withDependencies {
            $0.persistenceClient = .mock(
                routeDetails: [newest: Self.detail(newest),
                               single: Self.detail(single, [Self.path[0]]),
                               oldest: Self.detail(oldest)],
                routeIdsMissingMapThumbnail: [newest, single, oldest],
                onSaveRouteMapThumbnail: { id, _, _ in saved.withValue { $0.append(id) } }
            )
            $0.mapSnapshotClient = MapSnapshotClient { _, _, _, _ in Data([1]) }
        } operation: {
            await RouteMapThumbnail.backfill()
        }

        #expect(saved.value == [newest, oldest])
        #expect(stored == 2)
    }

    @Test("backfill stops at the first failed render: offline, every route would fail the same way")
    func backfillStopsAtFirstFailure() async {
        let first = UUID(), second = UUID()
        let renders = LockIsolated(0)

        let stored = await withDependencies {
            $0.persistenceClient = .mock(
                routeDetails: [first: Self.detail(first), second: Self.detail(second)],
                routeIdsMissingMapThumbnail: [first, second]
            )
            $0.mapSnapshotClient = MapSnapshotClient { _, _, _, _ in
                renders.withValue { $0 += 1 }
                throw MapSnapshotError.unavailable
            }
        } operation: {
            await RouteMapThumbnail.backfill()
        }

        #expect(stored == 0)
        // Light and dark for the first route at most; the second is never tried.
        #expect(renders.value <= 2)
    }
}
