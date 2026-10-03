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
    /// The grid's size, which turns an S07 drag's drop into a cell (#367).
    @State private var gridSize = CGSize.zero

    var body: some View {
        HStack(spacing: 0) {
            DashboardGridLayout {
                // S07's add-here slots (#368), drawn first so a remove button that overhangs into an
                // empty cell sits above its slot. Only edit mode draws them.
                ForEach(page.emptyCells, id: \.self) { cell in
                    DashboardEmptySlot(cell: cell) {
                        store.send(.emptyCellTapped(pageID: page.id, cell: cell))
                    }
                    .dashboardPlacement(at: cell, size: .oneByOne)
                }
                // A widget appears at most once per page (`DashboardLayoutValidator`), so its id is
                // the identity. A placement the catalog doesn't know is dropped at decode. Drawn in
                // reading order, so S07's remove button, which overhangs its widget up and to the
                // left, sits above the widgets there rather than under them.
                ForEach(page.placements.sorted { ($0.row, $0.column) < ($1.row, $1.column) }, id: \.widgetID) { placement in
                    if let widget = DashboardWidgetCatalog.widget(id: placement.widgetID) {
                        DashboardWidgetCell(widget: widget, placement: placement, page: page, gridSize: gridSize, store: store)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: CGSize.self, of: \.size) { gridSize = $0 }

            RadarLane(store: store)
        }
        // S07 (#141): a long press anywhere on the page — empty cells and the radar lane included
        // — enters edit mode. Simultaneous, so it still fires over a widget's own tap.
        .contentShape(Rectangle())
        .simultaneousGesture(LongPressGesture().onEnded { _ in
            store.send(.dashboardLongPressed, animation: .default)
        })
    }
}

/// One widget on the grid, with S07's edit chrome (#141) and its drag to move (#367).
///
/// In edit mode a press held for `liftDelay` lifts the widget — it stops wiggling, grows and draws
/// above the rest — and a drag carries it. The drop moves it to the cell nearest its top-left, or
/// swaps it with the same-size widget there; any other drop springs back. The hold is what leaves
/// a swipe to the `TabView`: a swipe moves before the hold ends, fails it, and pages.
private struct DashboardWidgetCell: View {
    let widget: any DashboardWidget.Type
    let placement: WidgetPlacement
    let page: DashboardPage
    let gridSize: CGSize
    let store: StoreOf<ActiveRideFeature>

    @Environment(\.isEditingDashboard) private var isEditing
    /// The drag's translation while the widget is lifted; `nil` when it isn't.
    @State private var lift: CGSize?

    /// How long a press holds before the widget lifts.
    private static let liftDelay = 0.25
    /// How much a lifted widget grows.
    private static let liftScale = 1.05
    private static let dropAnimation = Animation.spring

    var body: some View {
        widget.view(size: placement.size, store: store)
            // Fills its cells, centred like a `Grid` cell, whatever size it reports.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .dashboardEditCard(size: placement.size)
            .dashboardWiggle(phase: Double(placement.row * DashboardGrid.columns + placement.column) / 3, isHeld: lift != nil)
            // Inside the remove button, so a tap on it is never a drag.
            .gesture(DashboardLiftGesture(
                minimumDuration: Self.liftDelay,
                isEnabled: isEditing,
                onChanged: { lift = $0 },
                onEnded: drop
            ))
            .dashboardMoveActions(title: widget.title, placement: placement, targets: moveTargets, onMove: move)
            .dashboardRemoveButton(title: widget.title, size: placement.size) {
                store.send(.removeWidgetTapped(pageID: page.id, widgetID: placement.widgetID))
            }
            // Outside it, so the button travels with the card.
            .scaleEffect(lift == nil ? 1 : Self.liftScale)
            .offset(lift ?? .zero)
            .zIndex(lift == nil ? 0 : 1)
            .dashboardPlacement(placement)
    }

    /// Puts the widget down at the cell nearest its top-left, `translation` from where it was, or
    /// back where it was (`nil`, a cancelled drag). One animation carries it there from under the
    /// finger: the offset to zero and the frame to its new cell, or a springback when refused.
    private func drop(translation: CGSize?) {
        let origin = DashboardGrid.frame(for: placement, in: gridSize).origin
        let cell = translation.flatMap { translation in
            DashboardGrid.cell(
                nearest: CGPoint(x: origin.x + translation.width, y: origin.y + translation.height),
                in: gridSize
            )
        }
        withAnimation(Self.dropAnimation) {
            lift = nil
            if let cell {
                store.send(.moveWidget(pageID: page.id, widgetID: placement.widgetID, to: cell))
            }
        }
    }

    /// VoiceOver's Move actions, only worked out while editing.
    private var moveTargets: [(direction: DashboardGrid.Direction, cell: DashboardGrid.Cell)] {
        guard isEditing else { return [] }
        return DashboardGrid.Direction.allCases.compactMap { direction in
            page.moveTarget(for: placement.widgetID, direction).map { (direction, $0) }
        }
    }

    private func move(to cell: DashboardGrid.Cell) {
        store.send(.moveWidget(pageID: page.id, widgetID: placement.widgetID, to: cell), animation: Self.dropAnimation)
    }
}

/// S07's lift-and-drag (#367): a press held for `minimumDuration`, then dragged. `onChanged` gets
/// the translation from where the press lifted; `onEnded` gets the last one, or `nil` when the
/// system cancelled the touch.
///
/// UIKit's long press, not SwiftUI's `LongPressGesture` sequenced before a `DragGesture`: that held
/// every touch on a widget, so a swipe across one stopped paging the `TabView` (sim drive, #367).
/// UIKit's fails as soon as a touch moves before the hold ends, which leaves the swipe to the
/// pager — the way `UICollectionView` reorders inside a scroll view.
private struct DashboardLiftGesture: UIGestureRecognizerRepresentable {
    let minimumDuration: TimeInterval
    let isEnabled: Bool
    let onChanged: (CGSize) -> Void
    let onEnded: (CGSize?) -> Void

    final class Coordinator {
        var start = CGPoint.zero
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        UILongPressGestureRecognizer()
    }

    func updateUIGestureRecognizer(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        recognizer.minimumPressDuration = minimumDuration
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        // The window's space, not the widget's: the widget moves under the finger.
        let location = recognizer.location(in: nil)
        let translation = CGSize(width: location.x - context.coordinator.start.x, height: location.y - context.coordinator.start.y)
        switch recognizer.state {
        case .began:
            context.coordinator.start = location
            onChanged(.zero)
        case .changed:
            onChanged(translation)
        case .ended:
            onEnded(translation)
        case .cancelled, .failed:
            onEnded(nil)
        default:
            break
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
