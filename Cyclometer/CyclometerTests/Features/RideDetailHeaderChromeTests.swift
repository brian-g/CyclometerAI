import CoreGraphics
import Testing
@testable import Cyclometer

/// S15's map header against the scroll (#538): the fade, the pull-down stretch, and when the
/// title moves into the toolbar.
@Suite("RideDetailHeaderChrome")
struct RideDetailHeaderChromeTests {
    private let mapHeight: CGFloat = 437
    private let fade = Spacing.mapHeaderFade

    @Test("the map is whole at rest and pulled down, and gone once the title reaches the top")
    func opacityFallsAcrossTheScroll() {
        let distance = mapHeight - fade
        #expect(RideDetailHeaderChrome.mapOpacity(offset: 0, mapHeight: mapHeight, fade: fade) == 1)
        #expect(RideDetailHeaderChrome.mapOpacity(offset: -40, mapHeight: mapHeight, fade: fade) == 1)
        #expect(abs(RideDetailHeaderChrome.mapOpacity(offset: distance / 2, mapHeight: mapHeight, fade: fade) - 0.5) < 1e-9)
        #expect(RideDetailHeaderChrome.mapOpacity(offset: distance, mapHeight: mapHeight, fade: fade) == 0)
        #expect(RideDetailHeaderChrome.mapOpacity(offset: distance + 200, mapHeight: mapHeight, fade: fade) == 0)
    }

    @Test("a header no taller than its fade is whole at rest and gone once scrolled")
    func opacityWithNoDistance() {
        #expect(RideDetailHeaderChrome.mapOpacity(offset: 0, mapHeight: fade, fade: fade) == 1)
        #expect(RideDetailHeaderChrome.mapOpacity(offset: 1, mapHeight: fade, fade: fade) == 0)
    }

    @Test("pulling down grows the map by what was pulled; scrolling up never shrinks it")
    func stretchFollowsThePull() {
        #expect(RideDetailHeaderChrome.mapStretch(offset: 0, mapHeight: mapHeight) == 1)
        #expect(RideDetailHeaderChrome.mapStretch(offset: 120, mapHeight: mapHeight) == 1)
        let pulled = RideDetailHeaderChrome.mapStretch(offset: -100, mapHeight: mapHeight)
        #expect(abs(pulled * mapHeight - (mapHeight + 100)) < 1e-9)
        #expect(RideDetailHeaderChrome.mapStretch(offset: -100, mapHeight: 0) == 1)
    }

    @Test("the toolbar takes the title once its bottom reaches the toolbar's")
    func titleMovesIntoTheToolbar() {
        #expect(!RideDetailHeaderChrome.isTitleUnderToolbar(titleBottom: 120, toolbarBottom: 62))
        #expect(RideDetailHeaderChrome.isTitleUnderToolbar(titleBottom: 62, toolbarBottom: 62))
        #expect(RideDetailHeaderChrome.isTitleUnderToolbar(titleBottom: 10, toolbarBottom: 62))
    }
}
