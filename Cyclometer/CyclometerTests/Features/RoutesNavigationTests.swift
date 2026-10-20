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

        await store.send(.path(.push(id: 0, state: .route(RouteDetailFeature.State(summary: route)))))
        await store.send(.path(.element(id: 0, action: .route(.task))))
        await store.finish()
        // `finish()` lets the reads land; skipping is what applies them (`RouteDetailFeatureTests`).
        await store.skipReceivedActions()

        guard case let .route(pushed)? = store.state.path[id: 0] else {
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

        await store.send(.path(.push(id: 0, state: .route(RouteDetailFeature.State(summary: route))))) {
            $0.path[id: 0] = .route(RouteDetailFeature.State(summary: route))
        }
        await store.send(.path(.element(id: 0, action: .route(.useRouteButtonTapped))))
        await store.receive(\.path[id: 0].route.delegate.useRoute, route.reference)
        await store.receive(\.delegate.useRoute, route.reference)
    }

    // MARK: S20 → S15 (#426)

    @Test("a Previous Rides row opens S15 on that ride, under its own title")
    func aPreviousRideSeedsRideDetail() {
        var ride = RouteRideSummary.previewRides[0]
        ride.title = "Saturday Climb"

        let summary = RideListSummary(ride)

        #expect(summary == RideListSummary(id: ride.rideId, title: "Saturday Climb", startedAt: ride.startedAt,
                                           distanceMeters: ride.distanceMeters, durationSeconds: ride.durationSeconds))
    }

    @Test("a ride opened from S20 is pushed on the Routes stack and loads that ride")
    func aRideOpenedFromRouteDetailLoadsThroughTheStack() async {
        let route = Self.route
        let ride = RideListSummary(RouteRideSummary.previewRides[0])
        let stats = RideStats(averageSpeedMPS: 6, maxSpeedMPS: 11, routeId: route.id, routeName: route.name)
        let store = makeStore(persistenceClient: .mock(rideStats: [ride.id: stats], routes: [route]))
        // S15's Health read estimates max HR from age on this date.
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 1_750_000_000))
        store.exhaustivity = .off

        await store.send(.path(.push(id: 0, state: .route(RouteDetailFeature.State(summary: route)))))
        await store.send(.path(.push(id: 1, state: .ride(RideDetailFeature.State(summary: ride)))))
        await store.send(.path(.element(id: 1, action: .ride(.task))))
        await store.finish()
        await store.skipReceivedActions()

        #expect(store.state.path[id: 1, case: \.ride]?.summary == ride)
        #expect(store.state.path[id: 1, case: \.ride]?.stats == stats)
        #expect(store.state.path[id: 1, case: \.ride]?.route == route)
    }
}
