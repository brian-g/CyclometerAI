import ComposableArchitecture
import SwiftUI

/// S05.2 — the Route picker, pushed from the Start sheet's Route row (#196).
///
/// `Design.sketch` draws the frame — the title "Routes" and a back button — and leaves the body
/// blank. The body is S19's own rows, so a route looks the same wherever the rider meets it.
///
/// This view owns only what a snapshot must not run: the read. The screen itself is
/// `RoutePickerList`, as S20's is `RouteDetailList`.
struct RoutePickerView: View {
    let store: StoreOf<RoutePickerFeature>

    var body: some View {
        RoutePickerList(store: store)
            .navigationTitle("Routes")
            .navigationBarTitleDisplayMode(.inline)
            .task { await store.send(.task).finish() }
    }
}

/// S05.2's content: everything except the read, so a snapshot renders it from seeded state without
/// one landing mid-capture — and without navigation chrome, since an inline title renders white in
/// an offscreen capture.
struct RoutePickerList: View {
    let store: StoreOf<RoutePickerFeature>

    var body: some View {
        List {
            // First, and there whatever the read did, so a route S20 seeded can still be cleared
            // when the library can't be read.
            Section {
                ChoiceRow(isSelected: store.selection == nil) {
                    store.send(.routeTapped(nil))
                } label: {
                    Text("None")
                }
            }
            // Below it, one of three screens: nothing before the first read; the routes, or an empty
            // library, after it; and a failure that never claims the library is empty.
            switch store.library {
            case .loading:
                EmptyView()
            case .loaded(let routes):
                if routes.isEmpty {
                    message("No Routes", systemImage: RouteLibrary.symbolName,
                            "Import a route from the Routes tab to ride it.") { EmptyView() }
                } else {
                    Section {
                        ForEach(routes) { route in
                            // By id, not by value: the reference is only ever a pointer to the route.
                            ChoiceRow(isSelected: store.selection?.id == route.id) {
                                store.send(.routeTapped(route))
                            } label: {
                                RouteRow(route: route, unitSystem: store.unitSystem)
                            }
                        }
                    }
                }
            case .failed:
                message(RouteLibrary.loadFailedTitle, systemImage: "exclamationmark.triangle",
                        RouteLibrary.loadFailedMessage) {
                    Button("Try Again") { store.send(.retryButtonTapped) }
                }
            }
        }
    }

    /// A message in place of the routes section, on the list's own background.
    private func message<Actions: View>(
        _ title: String,
        systemImage: String,
        _ description: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        Section {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text(description)
            } actions: {
                actions()
            }
            .listRowBackground(Color.clear)
        }
    }
}

/// One choice: its label, and a checkmark on the chosen one.
///
/// The checkmark is always laid out and only its opacity changes, so the routes' distances stay one
/// right-aligned column whichever row is chosen.
private struct ChoiceRow<Content: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let label: Content

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                label
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.cyPrimary)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        // A `Button` in a `List` draws its label in the accent colour; the rows keep their own.
        .foregroundStyle(Color.cyTextPrimary)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Previews

// No `PersistenceClient.previewValue`: without the mock a preview reads the live store.
#Preview("Route Picker") {
    withDependencies {
        $0.defaultFileStorage = .inMemory
    } operation: {
        NavigationStack {
            RoutePickerView(
                store: Store(
                    initialState: RoutePickerFeature.State(selection: RouteSummary.previewRoutes[1].reference)
                ) {
                    RoutePickerFeature()
                } withDependencies: {
                    $0.persistenceClient = .mock(routes: RouteSummary.previewRoutes)
                }
            )
        }
    }
}

#Preview("Route Picker — empty library") {
    withDependencies {
        $0.defaultFileStorage = .inMemory
    } operation: {
        NavigationStack {
            RoutePickerView(
                store: Store(initialState: RoutePickerFeature.State()) {
                    RoutePickerFeature()
                } withDependencies: {
                    $0.persistenceClient = .mock(routes: [])
                }
            )
        }
    }
}
