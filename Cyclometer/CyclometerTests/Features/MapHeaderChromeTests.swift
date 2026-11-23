import CoreGraphics
import Testing
@testable import Cyclometer

/// The map header against the scroll (S15 #538, S20 #570): the fade, the pull-down stretch, and when the
/// title moves into the toolbar.
@Suite("MapHeaderChrome")
struct MapHeaderChromeTests {
    private let mapHeight: CGFloat = 437
    private let fade = Spacing.mapHeaderFade

    @Test("the map is whole at rest and pulled down, and gone once the title reaches the top")
    func opacityFallsAcrossTheScroll() {
        let distance = mapHeight - fade
        #expect(MapHeaderChrome.mapOpacity(offset: 0, mapHeight: mapHeight, fade: fade) == 1)
        #expect(MapHeaderChrome.mapOpacity(offset: -40, mapHeight: mapHeight, fade: fade) == 1)
        #expect(abs(MapHeaderChrome.mapOpacity(offset: distance / 2, mapHeight: mapHeight, fade: fade) - 0.5) < 1e-9)
        #expect(MapHeaderChrome.mapOpacity(offset: distance, mapHeight: mapHeight, fade: fade) == 0)
        #expect(MapHeaderChrome.mapOpacity(offset: distance + 200, mapHeight: mapHeight, fade: fade) == 0)
    }

    @Test("a header no taller than its fade is whole at rest and gone once scrolled")
    func opacityWithNoDistance() {
        #expect(MapHeaderChrome.mapOpacity(offset: 0, mapHeight: fade, fade: fade) == 1)
        #expect(MapHeaderChrome.mapOpacity(offset: 1, mapHeight: fade, fade: fade) == 0)
    }

    @Test("pulling down grows the map by what was pulled; scrolling up never shrinks it")
    func stretchFollowsThePull() {
        #expect(MapHeaderChrome.mapStretch(offset: 0, mapHeight: mapHeight) == 1)
        #expect(MapHeaderChrome.mapStretch(offset: 120, mapHeight: mapHeight) == 1)
        let pulled = MapHeaderChrome.mapStretch(offset: -100, mapHeight: mapHeight)
        #expect(abs(pulled * mapHeight - (mapHeight + 100)) < 1e-9)
        #expect(MapHeaderChrome.mapStretch(offset: -100, mapHeight: 0) == 1)
    }

    @Test("the header is half the screen, in whole points")
    func heightIsHalfTheScreen() {
        #expect(MapHeaderChrome.mapHeight(screenHeight: 874) == 437)
        #expect(MapHeaderChrome.mapHeight(screenHeight: 875) == 438)
    }

    @Test("the toolbar takes the title once its bottom reaches the toolbar's")
    func titleMovesIntoTheToolbar() {
        #expect(!MapHeaderChrome.isTitleUnderToolbar(titleBottom: 120, toolbarBottom: 62))
        #expect(MapHeaderChrome.isTitleUnderToolbar(titleBottom: 62, toolbarBottom: 62))
        #expect(MapHeaderChrome.isTitleUnderToolbar(titleBottom: 10, toolbarBottom: 62))
    }
}
