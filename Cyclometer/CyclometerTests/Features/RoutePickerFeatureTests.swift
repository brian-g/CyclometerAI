import Testing
import Foundation
import ComposableArchitecture
@testable import Cyclometer

/// S05.2 — the Route picker's own reducer (#196). How its answer reaches the sheet and the ride is
/// `StartSheetFeatureTests` and `AppRouteSelectionTests`.
@MainActor
@Suite("RoutePickerFeature")
struct RoutePickerFeatureTests {

    private static let routes = RouteSummary.previewRoutes

    /// Same in-memory `@Shared` idiom as `RoutesNavigationTests.makeStore`; the state is built inside
    /// the scope too, so its preferences land in the store's storage.
    private func makeStore(
        selection: RouteReference? = nil,
        library: RoutePickerFeature.Library = .loading,
        persistenceClient: PersistenceClient = .mock(routes: RouteSummary.previewRoutes)
    ) -> TestStoreOf<RoutePickerFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            var state = RoutePickerFeature.State(selection: selection)
            state.library = library
            return TestStore(initialState: state) {
                RoutePickerFeature()
            } withDependencies: {
                $0.persistenceClient = persistenceClient
                $0.defaultFileStorage = storage
            }
        }
    }

    private static var failingClient: PersistenceClient {
        var client = PersistenceClient.mock()
        client.fetchRoutes = { throw PersistenceError.rideNotFound }
        return client
    }

    @Test("Appearing lists every saved route, in the order the store returns them")
    func appearingLoadsTheLibrary() async {
        let store = makeStore()

        await store.send(.task)
        await store.receive(.routesResponse(.success(Self.routes))) {
            $0.library = .loaded(Self.routes)
        }
    }

    @Test("An empty library is loaded and empty, not failed")
    func emptyLibraryIsNotAFailure() async {
        let store = makeStore(persistenceClient: .mock(routes: []))

        await store.send(.task)
        await store.receive(.routesResponse(.success([]))) {
            $0.library = .loaded([])
        }
    }

    /// What #193 got wrong on S19: a read that failed must not look like a library with nothing in it.
    @Test("A failed read is its own state, never an empty library")
    func failedReadIsDistinctFromEmpty() async {
        let store = makeStore(persistenceClient: Self.failingClient)

        await store.send(.task)
        await store.receive(.routesResponse(.failure(PersistenceFailure()))) {
            $0.library = .failed
        }
    }

    /// The failure screen's "Try Again": the retry its "Try again in a moment" copy promises.
    @Test("Try Again after a failed read reads the library again")
    func tryAgainReadsTheLibraryAgain() async {
        let store = makeStore(library: .failed)

        await store.send(.retryButtonTapped) {
            $0.library = .loading
        }
        await store.receive(.routesResponse(.success(Self.routes))) {
            $0.library = .loaded(Self.routes)
        }
    }

    @Test("Tapping a route checks it and hands it back")
    func tappingARouteHandsItBack() async {
        let store = makeStore()
        let route = Self.routes[1]

        await store.send(.routeTapped(route)) {
            $0.selection = route.reference
        }
        await store.receive(.delegate(.routeSelected(route.reference)))
    }

    @Test("Tapping None clears the choice and hands back nil")
    func tappingNoneHandsBackNil() async {
        let store = makeStore(selection: Self.routes[1].reference)

        await store.send(.routeTapped(nil)) {
            $0.selection = nil
        }
        await store.receive(.delegate(.routeSelected(nil)))
    }
}
