import SwiftUI

/// Lays a dashboard page's widgets out on the 2 × 7 grid, each at the frame
/// `DashboardGrid.frame(for:in:)` gives its placement (#139). Positional rather than a `Grid` of
/// rows, so empty cells stay empty and a row is always one seventh of the height, never stretched
/// into space a part-filled page leaves (#82).
struct DashboardGridLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            guard let placement = subview[DashboardPlacementKey.self] else { continue }
            let frame = DashboardGrid.frame(for: placement, in: bounds.size)
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(frame.size)
            )
        }
    }
}

private struct DashboardPlacementKey: LayoutValueKey {
    static let defaultValue: WidgetPlacement? = nil
}

extension View {
    /// Where `DashboardGridLayout` puts this view. Every child needs one: SwiftUI centres a child
    /// the layout doesn't place over the whole grid, at the grid's full size.
    func dashboardPlacement(_ placement: WidgetPlacement) -> some View {
        layoutValue(key: DashboardPlacementKey.self, value: placement)
    }
}
