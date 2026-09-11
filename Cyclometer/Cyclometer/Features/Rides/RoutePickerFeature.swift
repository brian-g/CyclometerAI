import ComposableArchitecture
import Foundation

/// S05.2 — the Route picker: which saved route, if any, the ride about to start follows (#196).
///
/// Pushed on the Start sheet's own stack from its Route row. A choice goes back as a delegate and
/// `StartSheetFeature` pops, so the answer and the navigation land in one reducer pass.
///
/// A list and nothing more. Importing, filtering and the map are S19's — the Start sheet offers no
/// `fileImporter`. Nothing hangs off `onDisappear` (`tasks/lessons.md`): the read runs from `.task`
/// or a retry, and `.forEach` cancels a popped element's effects, as `.ifLet` does the whole stack's
/// when the sheet goes.
@Reducer
struct RoutePickerFeature {

    /// The library read, in the three states S05.2 draws differently (`tasks/lessons.md`, #193). One
    /// value rather than two flags, so a failure can never sit beside a stale list, and a failed read
    /// can never look like an empty library.
    enum Library: Equatable {
        case loading
        case loaded([RouteSummary])
        case failed
    }

    @ObservableState
    struct State: Equatable {
        /// Row distances follow the S12 units picker, the same read-through `RoutesFeature` does.
        @Shared(.appPreferences) var preferences

        /// The sheet's current answer, nil for a free ride — the row that carries the checkmark.
        var selection: RouteReference?

        var library: Library = .loading

        init(selection: RouteReference? = nil) {
            self.selection = selection
        }

        var unitSystem: UnitSystem { preferences.preferredUnit }
    }

    enum Action: Equatable {
        case task
        case retryButtonTapped
        case routesResponse(Result<[RouteSummary], PersistenceFailure>)
        /// Nil is the None row.
        case routeTapped(RouteSummary?)
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            /// The rider's choice, nil for None, on its way to `StartSheetFeature`, which owns it.
            case routeSelected(RouteReference?)
        }
    }

    @Dependency(\.persistenceClient) var persistenceClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {

            case .task:
                return load()

            case .retryButtonTapped:
                // Back to the not-read-yet screen while the read runs, rather than leaving the failure
                // up over a read that may already be succeeding.
                state.library = .loading
                return load()

            case .routesResponse(.success(let routes)):
                state.library = .loaded(routes)
                return .none

            case .routesResponse(.failure):
                state.library = .failed
                return .none

            case .routeTapped(let route):
                // Checked here as well as handed back, so the mark moves to the tapped row while the
                // pop animates rather than sitting on the old answer.
                state.selection = route?.reference
                return .send(.delegate(.routeSelected(route?.reference)))

            case .delegate:
                return .none
            }
        }
    }

    /// Summaries only: a row needs a name, a terrain line and a distance, never the polyline
    /// (`Route.swift:138-140`). The same read S19 makes, failure handling included.
    private func load() -> Effect<Action> {
        .run { [persistenceClient] send in
            await send(.routesResponse(await persistenceClient.loadRoutes()))
        }
    }
}
