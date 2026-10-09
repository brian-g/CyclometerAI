import SwiftUI

/// Lays a dashboard page's widgets out on the 2 × 7 grid, each at the frame
/// `DashboardGrid.frame(at:size:in:)` gives its placement (#139). Positional rather than a `Grid` of
/// rows, so empty cells stay empty and a row is always one seventh of the height, never stretched
/// into space a part-filled page leaves (#82).
struct DashboardGridLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            guard let slot = subview[DashboardPlacementKey.self] else { continue }
            let frame = DashboardGrid.frame(at: slot.cell, size: slot.size, in: bounds.size)
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(frame.size)
            )
        }
    }
}

/// A child's top-left cell and size: a widget's placement, less which widget it is, so S07's
/// empty-cell slots (#368) are placed by the same math.
private struct DashboardPlacementKey: LayoutValueKey {
    static let defaultValue: (cell: DashboardGrid.Cell, size: WidgetSize)? = nil
}

extension View {
    /// Where `DashboardGridLayout` puts this view. Every child needs one: SwiftUI centres a child
    /// the layout doesn't place over the whole grid, at the grid's full size.
    func dashboardPlacement(_ placement: WidgetPlacement) -> some View {
        dashboardPlacement(at: placement.cell, size: placement.size)
    }

    /// Where `DashboardGridLayout` puts a `size` view with its top-left at `cell`.
    func dashboardPlacement(at cell: DashboardGrid.Cell, size: WidgetSize) -> some View {
        layoutValue(key: DashboardPlacementKey.self, value: (cell, size))
    }
}
