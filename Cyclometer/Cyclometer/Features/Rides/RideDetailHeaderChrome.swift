import CoreGraphics

/// How S15's map header answers the scroll (#538), as arithmetic so it is tested without
/// scrolling a view. `offset` is how far the list has scrolled from its top: positive scrolled
/// up, negative pulled down past the top.
enum RideDetailHeaderChrome {
    /// The header's share of the screen's height (UX.md §S15).
    static let mapHeightFraction: CGFloat = 0.5

    /// The map's opacity: whole at rest, falling linearly to nothing as the title area, which
    /// starts `fade` above the map's bottom, scrolls up to the top of the screen.
    static func mapOpacity(offset: CGFloat, mapHeight: CGFloat, fade: CGFloat) -> Double {
        let distance = mapHeight - fade
        guard distance > 0 else { return offset > 0 ? 0 : 1 }
        return Double(1 - min(max(offset / distance, 0), 1))
    }

    /// How much the map grows when the rider pulls down past the top: enough that its bottom
    /// stays on the content that was pulled down, with its top held at the top of the screen.
    /// 1 at rest and when scrolled up.
    static func mapStretch(offset: CGFloat, mapHeight: CGFloat) -> CGFloat {
        guard offset < 0, mapHeight > 0 else { return 1 }
        return (mapHeight - offset) / mapHeight
    }

    /// Whether the title has scrolled under the toolbar, so the toolbar shows it instead.
    /// `titleBottom` and `toolbarBottom` are in the same space: the screen's.
    static func isTitleUnderToolbar(titleBottom: CGFloat, toolbarBottom: CGFloat) -> Bool {
        titleBottom <= toolbarBottom
    }
}
