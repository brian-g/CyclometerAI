import Testing
import Foundation
import ComposableArchitecture
@testable import Cyclometer

/// The ride's route, from where it is chosen to the ride that follows it: S20's "Use This Route"
/// (#195) and S05.2's picker (#196), through the Start sheet, into `ActiveRideFeature`.
///
/// Built on `StartSheetPresentationTests.makeStore`, whose call log is what shows the sheet opened
/// the way the toolbar's Start Ride opens it — pairing scan included. The toolbar button itself
/// renders as nothing in a snapshot, so this is its coverage.
@MainActor
@Suite("AppFeature — the ride's route")
struct AppRouteSelectionTests {
    typealias ScanCall = StartSheetPresentationTests.ScanCall

    /// "Summit Climb".
    private static let route = RouteSummary.previewRoutes[1]
    private static let begun: [ScanCall] = [.begin(.speedCadence), .begin(.radar), .begin(.heartRate)]

    /// Pushes S20 for `route` on the Routes tab and taps Use This Route, as the rider would.
    private func useRoute(on store: TestStoreOf<AppFeature>) async {
        await store.send(.routes(.path(.push(id: 0, state: .detail(RouteDetailFeature.State(summary: Self.route))))))
        await store.send(.routes(.path(.element(id: 0, action: .detail(.useRouteButtonTapped)))))
        await store.receive(\.routes.delegate.useRoute, Self.route.reference)
    }

    /// Taps the sheet's own Start Ride. The delegate is *received*, not sent, so the route that
    /// arrives is the one the sheet was holding.
    private func startRide(on store: TestStoreOf<AppFeature>, expecting route: RouteReference?) async {
        await store.send(.startSheet(.presented(.startRideButtonTapped)))
        await store.receive(\.startSheet.presented.delegate.startRide, route)
    }

    @Test("Use This Route opens the Start sheet on that route, with its pairing scan")
    func useRouteOpensTheStartSheet() async {
        let log = LockIsolated<[ScanCall]>([])
        let store = StartSheetPresentationTests.makeStore(into: log)
        store.exhaustivity = .off(showSkippedAssertions: false)

        await useRoute(on: store)
        await store.finish()

        #expect(store.state.startSheet?.route == Self.route.reference)
        #expect(log.value == Self.begun)
    }

    @Test("Use This Route does nothing while a ride is recording")
    func useRouteIsIgnoredDuringARide() async {
        let log = LockIsolated<[ScanCall]>([])
        let store = StartSheetPresentationTests.makeStore(into: log) {
            AppFeature.State(activeRide: ActiveRideFeature.State())
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await useRoute(on: store)
        await store.finish()

        #expect(store.state.startSheet == nil)
        #expect(log.value.isEmpty)
    }

    /// Asserted on a *reopened* sheet. The dismissed one is nil, so an assertion about its route
    /// would pass whatever the code did.
    @Test("After Cancel, the next Start Ride opens on a free ride")
    func dismissingTheSheetForgetsTheRoute() async {
        let log = LockIsolated<[ScanCall]>([])
        let store = StartSheetPresentationTests.makeStore(into: log)
        store.exhaustivity = .off(showSkippedAssertions: false)

        await useRoute(on: store)
        await store.send(.startSheet(.dismiss))
        await store.send(.startRideButtonTapped)
        await store.finish()

        #expect(store.state.startSheet != nil)
        #expect(store.state.startSheet?.route == nil)
    }

    @Test("Starting the ride hands S20's route to the ride")
    func startingTheRideCarriesTheRoute() async {
        let log = LockIsolated<[ScanCall]>([])
        let store = StartSheetPresentationTests.makeStore(into: log)
        store.exhaustivity = .off(showSkippedAssertions: false)

        await useRoute(on: store)
        await startRide(on: store, expecting: Self.route.reference)
        await store.finish()

        #expect(store.state.activeRide?.route == Self.route.reference)
        #expect(store.state.startSheet == nil)
    }

    /// The other way in while the sheet is already up — the toolbar's Start Ride after Use This Route —
    /// must not replace the sheet and lose the route it was opened on, nor take a second scan.
    @Test("Start Ride while the sheet is up keeps the route Use This Route set")
    func startRideWhileTheSheetIsUpKeepsTheRoute() async {
        let log = LockIsolated<[ScanCall]>([])
        let store = StartSheetPresentationTests.makeStore(into: log)
        store.exhaustivity = .off(showSkippedAssertions: false)

        await useRoute(on: store)
        await store.send(.startRideButtonTapped)
        await store.finish()

        #expect(store.state.startSheet?.route == Self.route.reference)
        #expect(log.value == Self.begun)
    }

    @Test("A route picked on S05.2 reaches the ride")
    func pickedRouteReachesTheRide() async throws {
        let log = LockIsolated<[ScanCall]>([])
        let store = StartSheetPresentationTests.makeStore(into: log)
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.startRideButtonTapped)
        // What the Route row pushes, built in the store's own dependency scope so the picker's
        // `@Shared` preferences live in `makeStore`'s in-memory storage, not the test context's.
        let pushed = withDependencies { $0 = store.dependencies } operation: {
            store.state.startSheet?.routePicker
        }
        let picker = try #require(pushed)
        await store.send(.startSheet(.presented(.path(.push(id: 0, state: picker)))))
        await store.send(.startSheet(.presented(.path(.element(id: 0, action: .routePicker(.routeTapped(Self.route)))))))
        await store.receive(\.startSheet.presented.path[id: 0].routePicker.delegate.routeSelected, Self.route.reference)

        #expect(store.state.startSheet?.route == Self.route.reference)
        #expect(store.state.startSheet?.path.isEmpty == true)

        await startRide(on: store, expecting: Self.route.reference)
        await store.finish()

        #expect(store.state.activeRide?.route == Self.route.reference)
    }
}
