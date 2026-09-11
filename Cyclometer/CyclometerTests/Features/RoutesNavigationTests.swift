import Testing
import Foundation
import ComposableArchitecture
@testable import Cyclometer

/// S19 → S20: the Routes tab's navigation stack (#195).
///
/// Stack-based because S20 is one screen per route: a `NavigationLink(state:)` row pushes that
/// route's own `RouteDetailFeature.State`, which is what tells the reducer which one was tapped.
@MainActor
@Suite("RoutesFeature — route detail")
struct RoutesNavigationTests {

    /// "Summit Climb": elevation on every point.
    private static let route = RouteSummary.previewRoutes[1]

    /// Same in-memory `@Shared` idiom as `RoutesFeatureTests.makeStore`.
    private func makeStore(persistenceClient: PersistenceClient = .mock()) -> TestStoreOf<RoutesFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            TestStore(initialState: RoutesFeature.State()) {
                RoutesFeature()
            } withDependencies: {
                $0.persistenceClient = persistenceClient
                $0.defaultFileStorage = storage
            }
        }
    }

    @Test("a pushed route loads its geometry and its rides through the stack")
    func aPushedRouteLoadsThroughTheStack() async {
        let route = Self.route
        let detail = RouteDetail.previewRouteDetails[route.id]!
        let store = makeStore(persistenceClient: .mock(
            routeDetails: RouteDetail.previewRouteDetails,
            ridesByRoute: [route.id: RouteRideSummary.previewRides]
        ))
        // The two reads are merged, so their arrival order is the scheduler's; the settled state
        // is what is asserted.
        store.exhaustivity = .off

        await store.send(.path(.push(id: 0, state: .detail(RouteDetailFeature.State(summary: route)))))
        await store.send(.path(.element(id: 0, action: .detail(.task))))
        await store.finish()
        // `finish()` lets the reads land; skipping is what applies them (`RouteDetailFeatureTests`).
        await store.skipReceivedActions()

        guard case let .detail(pushed)? = store.state.path[id: 0] else {
            Issue.record("S20 is not on the stack")
            return
        }
        #expect(pushed.summary == route)
        #expect(pushed.coordinates == detail.coordinates)
        #expect(pushed.previousRides == RouteRideSummary.previewRides)
    }

    @Test("Use This Route leaves the stack as the Routes feature's own delegate action")
    func useRouteBubblesOutOfTheStack() async {
        let route = Self.route
        let store = makeStore()

        await store.send(.path(.push(id: 0, state: .detail(RouteDetailFeature.State(summary: route))))) {
            $0.path[id: 0] = .detail(RouteDetailFeature.State(summary: route))
        }
        await store.send(.path(.element(id: 0, action: .detail(.useRouteButtonTapped))))
        await store.receive(\.path[id: 0].detail.delegate.useRoute, route.reference)
        await store.receive(\.delegate.useRoute, route.reference)
    }
}
