import ComposableArchitecture
import SwiftUI

/// S05.2 — the Route picker, pushed from the Start sheet's Route row (#196).
///
/// `Design.sketch` draws the frame — the title "Routes" and a back button — and leaves the body
/// blank. The body is S19's own rows, so a route looks the same wherever the rider meets it.
struct RoutePickerView: View {
    let store: StoreOf<RoutePickerFeature>

    var body: some View {
        RoutePickerList(
            routes: store.routes,
            selection: store.selection,
            hasLoaded: store.hasLoaded,
            loadFailed: store.loadFailed,
            unitSystem: store.unitSystem,
            onSelect: { store.send(.routeTapped($0)) }
        )
        .navigationTitle("Routes")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.send(.task).finish() }
    }
}

/// The picker's list, from plain values rather than a store, so `StartSheetSnapshotTests` can render
/// it without navigation chrome — an inline title renders white in an offscreen capture — and without
/// a read landing mid-capture.
struct RoutePickerList: View {
    let routes: [RouteSummary]
    let selection: RouteReference?
    let hasLoaded: Bool
    let loadFailed: Bool
    let unitSystem: UnitSystem
    /// Nil is None.
    let onSelect: (RouteSummary?) -> Void

    var body: some View {
        List {
            // First, and there whatever the read did, so a route S20 seeded can still be cleared
            // when the library can't be read.
            Section {
                ChoiceRow(isSelected: selection == nil) {
                    onSelect(nil)
                } label: {
                    Text("None")
                }
            }
            // Three distinct screens below it: nothing before the first read; the routes, or an empty
            // library, after it; and a failure that never claims the library is empty.
            if hasLoaded {
                if routes.isEmpty {
                    message("No Routes", systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                            "Import a route from the Routes tab to ride it.")
                } else {
                    Section {
                        ForEach(routes) { route in
                            // By id, not by value: the reference is only ever a pointer to the route.
                            ChoiceRow(isSelected: selection?.id == route.id) {
                                onSelect(route)
                            } label: {
                                RouteRow(route: route, unitSystem: unitSystem)
                            }
                        }
                    }
                }
            } else if loadFailed {
                message("Couldn't Load Routes", systemImage: "exclamationmark.triangle",
                        "Your saved routes couldn't be read. Try again in a moment.")
            }
        }
    }

    /// A message in place of the routes section, on the list's own background.
    private func message(_ title: String, systemImage: String, _ description: String) -> some View {
        Section {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text(description)
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
