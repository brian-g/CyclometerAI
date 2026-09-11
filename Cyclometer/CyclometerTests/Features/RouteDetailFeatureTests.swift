import Testing
import Foundation
import ComposableArchitecture
@testable import Cyclometer

/// S20 — Route Detail reading its route and its rides from the store rather than the
/// `RouteStub` the prototype was built on (#195).
///
/// The two reads in `.task` are merged, so which lands first is up to the scheduler. These tests
/// assert on the state once both have settled rather than on the order they arrived in: `finish()`
/// lets them land, and `skipReceivedActions()` is what applies them. A `TestStore`'s `state` moves
/// past a received action only once that action is received or skipped — its reducer records the
/// resulting state without adopting it (`TestStore.swift`, `TestReducer`'s `.receive` branch) — so
/// asserting straight after `finish()` reads the state from before either read landed. The first
/// version of this suite did exactly that, and two of its tests passed with nothing loaded.
@MainActor
@Suite("RouteDetailFeature")
struct RouteDetailFeatureTests {

    // MARK: Harness

    /// Same in-memory `@Shared` idiom as `RoutesFeatureTests.makeStore`.
    private func makeStore(
        summary: RouteSummary,
        persistenceClient: PersistenceClient
    ) -> TestStoreOf<RouteDetailFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            TestStore(initialState: RouteDetailFeature.State(summary: summary)) {
                RouteDetailFeature()
            } withDependencies: {
                $0.persistenceClient = persistenceClient
                $0.defaultFileStorage = storage
            }
        }
    }

    /// "River Loop" carries `<ele>` on every point; "Coffee Spin" carries none at all.
    private static let withElevation = RouteSummary.previewRoutes[0]
    private static let withoutElevation = RouteSummary.previewRoutes[3]

    private static func detail(_ summary: RouteSummary) -> RouteDetail {
        RouteDetail.previewRouteDetails[summary.id]!
    }

    // MARK: Loading

    @Test("task loads the polyline, its elevation profile and the route's rides")
    func taskLoadsGeometryProfileAndRides() async {
        let route = Self.withElevation
        let detail = Self.detail(route)
        let store = makeStore(summary: route, persistenceClient: .mock(
            routeDetails: [route.id: detail],
            ridesByRoute: [route.id: RouteRideSummary.previewRides]
        ))
        store.exhaustivity = .off

        await store.send(.task)
        await store.finish()
        await store.skipReceivedActions()

        #expect(store.state.coordinates == detail.coordinates)
        #expect(store.state.elevationProfileMeters == RouteGeometry.elevationProfile(
            detail.coordinates, sampleCount: RouteDetailFeature.elevationProfileSampleCount
        ))
        #expect(store.state.elevationProfileMeters?.count == RouteDetailFeature.elevationProfileSampleCount)
        #expect(store.state.previousRides == RouteRideSummary.previewRides)
    }

    @Test("a route with no <ele> loads its polyline and no profile")
    func aRouteWithoutElevationHasNoProfile() async {
        let route = Self.withoutElevation
        let detail = Self.detail(route)
        let store = makeStore(summary: route, persistenceClient: .mock(routeDetails: [route.id: detail]))
        store.exhaustivity = .off

        await store.send(.task)
        await store.finish()
        await store.skipReceivedActions()

        #expect(store.state.coordinates == detail.coordinates)
        #expect(store.state.elevationProfileMeters == nil)
    }

    @Test("a route that has never been ridden leaves Previous Rides empty")
    func aNeverRiddenRouteHasNoPreviousRides() async {
        let route = Self.withElevation
        let store = makeStore(summary: route, persistenceClient: .mock(routeDetails: [route.id: Self.detail(route)]))
        store.exhaustivity = .off

        await store.send(.task)
        await store.finish()
        await store.skipReceivedActions()

        // The route has to have loaded too, or an empty Previous Rides proves nothing about the
        // rides read — it is also what the state looks like before anything lands.
        #expect(store.state.coordinates == Self.detail(route).coordinates)
        #expect(store.state.previousRides.isEmpty)
    }

    /// Only a route deleted out from under the screen resolves to nil; a throw is SwiftData failing.
    /// Either way the rider keeps the name, distance and climb the screen was seeded with.
    @Test("a route that cannot be read leaves the screen on its summary", arguments: [false, true])
    func anUnreadableRouteKeepsTheSummary(throwing: Bool) async {
        let route = Self.withElevation
        var client = PersistenceClient.mock()
        if throwing {
            client.fetchRoute = { _ in throw PersistenceError.rideNotFound }
        }
        let store = makeStore(summary: route, persistenceClient: client)
        store.exhaustivity = .off

        await store.send(.task)
        await store.finish()
        await store.skipReceivedActions()

        #expect(store.state.summary == route)
        #expect(store.state.coordinates.isEmpty)
        #expect(store.state.elevationProfileMeters == nil)
    }

    @Test("a failed rides read leaves Previous Rides hidden rather than failing the screen")
    func aFailedRidesReadHidesTheSection() async {
        let route = Self.withElevation
        let detail = Self.detail(route)
        var client = PersistenceClient.mock(routeDetails: [route.id: detail])
        client.fetchRouteRides = { _ in throw PersistenceError.rideNotFound }
        let store = makeStore(summary: route, persistenceClient: client)
        store.exhaustivity = .off

        await store.send(.task)
        await store.finish()
        await store.skipReceivedActions()

        #expect(store.state.previousRides.isEmpty)
        #expect(store.state.coordinates == detail.coordinates, "the route read is independent of the rides read")
    }

    // MARK: Use This Route

    @Test("Use This Route hands the route to the parent as a delegate action")
    func useRouteSendsTheDelegate() async {
        let route = Self.withElevation
        let store = makeStore(summary: route, persistenceClient: .mock())

        await store.send(.useRouteButtonTapped)
        await store.receive(\.delegate.useRoute, RouteReference(id: route.id, name: route.name))
    }
}
