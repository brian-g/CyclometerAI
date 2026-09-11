import Testing
import Foundation
import ComposableArchitecture
@testable import Cyclometer

/// S20's "Use This Route" end to end (#195): from the button on a pushed route, out through
/// `RoutesFeature`'s delegate, to the Start sheet `AppFeature` owns.
///
/// Built on `StartSheetPresentationTests.makeStore`, whose call log is what shows the sheet opened
/// the way the toolbar's Start Ride opens it — pairing scan included. The toolbar button itself
/// renders as nothing in a snapshot, so this is its coverage.
@MainActor
@Suite("AppFeature — Use This Route")
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

    @Test("Use This Route records the route and opens the Start sheet with its pairing scan")
    func useRouteOpensTheStartSheet() async {
        let log = LockIsolated<[ScanCall]>([])
        let store = StartSheetPresentationTests.makeStore(into: log)
        store.exhaustivity = .off(showSkippedAssertions: false)

        await useRoute(on: store)
        await store.finish()

        #expect(store.state.activeRoute == Self.route.reference)
        #expect(store.state.startSheet != nil)
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

        #expect(store.state.activeRoute == nil)
        #expect(store.state.startSheet == nil)
        #expect(log.value.isEmpty)
    }

    /// S05.1's route row is read-only (#196), so a route that outlived its sheet could never be
    /// un-chosen: every later Start Ride would carry it.
    @Test("Cancelling the sheet forgets the route, so the next Start Ride is a free ride")
    func dismissingTheSheetForgetsTheRoute() async {
        let log = LockIsolated<[ScanCall]>([])
        let store = StartSheetPresentationTests.makeStore(into: log)
        store.exhaustivity = .off(showSkippedAssertions: false)

        await useRoute(on: store)
        await store.send(.startSheet(.dismiss))
        await store.finish()

        #expect(store.state.activeRoute == nil)
    }

    @Test("Starting the ride clears the route, so the next sheet opens without it")
    func startingTheRideClearsTheRoute() async {
        let log = LockIsolated<[ScanCall]>([])
        let store = StartSheetPresentationTests.makeStore(into: log)
        store.exhaustivity = .off(showSkippedAssertions: false)

        await useRoute(on: store)
        await store.send(.startSheet(.presented(.delegate(.startRide))))
        await store.finish()

        #expect(store.state.activeRoute == nil)
    }
}
