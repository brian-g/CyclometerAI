import SwiftUI
import ComposableArchitecture

/// One dashboard page: its widgets on the 2 × 7 grid (#139), with the radar lane beside them.
///
/// The parent's `TabView` ignores the safe areas, so this measures the full screen and a widget
/// in rows 1–2 or 6–7 bleeds under the Dynamic Island or behind the floating toolbar (UX.md §S05
/// "Map widget — safe area bleed").
struct DashboardPageView: View {
    let page: DashboardPage
    let store: StoreOf<ActiveRideFeature>

    var body: some View {
        HStack(spacing: 0) {
            DashboardGridLayout {
                // A widget appears at most once per page (`DashboardLayoutValidator`), so its id is
                // the identity. A placement the catalog doesn't know is dropped at decode.
                ForEach(page.placements, id: \.widgetID) { placement in
                    if let widget = DashboardWidgetCatalog.widget(id: placement.widgetID) {
                        widget.view(size: placement.size, store: store)
                            // Fills its cells, centred like a `Grid` cell, whatever size it reports.
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .dashboardPlacement(placement)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            RadarLane(store: store)
        }
    }
}

/// W7 — Radar full-height lane (S06), beside the grid, not in it, on every page.
///
/// Per PRD §8.2/UX.md §S06 it represents the road behind the rider and needs the dashboard's full
/// height to space vehicles readably, which no grid row can give it. `isRadarSidebarVisible`
/// reserves its width only once radar has paired this ride; the grid gets the rest. Its own view so
/// radar updates, several a second, redraw only the lane and not every page's grid.
///
/// `RadarColumnView`'s body is a `GeometryReader`, which has no intrinsic height of its own —
/// sitting next to the grid in an `HStack`, it collapses toward a tiny cross-axis size unless told
/// to be greedy. `.frame(maxHeight: .infinity)` makes it claim the same full height the grid gets,
/// to the physical top and bottom edges.
private struct RadarLane: View {
    let store: StoreOf<ActiveRideFeature>

    var body: some View {
        if store.isRadarSidebarVisible {
            RadarColumnView(targets: store.radarTargets, isOffline: store.isRadarOffline)
                .frame(width: Spacing.radarColumnWidth)
                .frame(maxHeight: .infinity)
                .ignoresSafeArea()
        }
    }
}
