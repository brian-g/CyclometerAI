import ComposableArchitecture
import CoreGraphics
import Foundation
import Testing
@testable import Cyclometer

struct DashboardLayoutTests {
    private func page(_ placements: WidgetPlacement...) -> DashboardPage {
        DashboardPage(placements: placements)
    }

    @Test("Catalog ids are unique and every widget supports at least one size")
    func catalogIsWellFormed() {
        let ids = DashboardWidgetCatalog.all.map { $0.id }
        #expect(Set(ids).count == ids.count)
        for widget in DashboardWidgetCatalog.all {
            #expect(!widget.supportedSizes.isEmpty, "\(widget.id) supports no size")
            #expect(DashboardWidgetCatalog.widget(id: widget.id) != nil)
        }
    }

    @Test("Every factory page satisfies the layout rules")
    func factoryIsValid() {
        for page in DashboardLayout.factory.pages {
            #expect(DashboardLayoutValidator.violations(in: page).isEmpty)
        }
        #expect(DashboardLayoutValidator.isValid(.factory))
    }

    /// The factory's later pages are a showcase (#139): every widget, at every size it supports.
    @Test("The factory layout shows every widget at every supported size")
    func factoryCoversEveryWidgetAndSize() {
        let placed = Set(DashboardLayout.factory.pages.flatMap(\.placements).map { "\($0.widgetID)-\($0.size)" })
        for widget in DashboardWidgetCatalog.all {
            for size in widget.supportedSizes {
                #expect(placed.contains("\(widget.id)-\(size)"), "\(widget.id) \(size) is never shown")
            }
        }
    }

    /// Page 1 must land where the hand-built grid before #139 put each widget: rows of height/7,
    /// columns of width/2. One deliberate change: Cadence 2×1 now spans both columns (the old
    /// `GridRow` lacked `.gridCellColumns(2)`, so it got one).
    @Test("Factory page 1 lays out as the hand-built grid did")
    func factoryPageOneGeometry() {
        let screen = CGSize(width: 402, height: 874)
        let unit = screen.height / 7
        let half = screen.width / 2
        let frames = Dictionary(uniqueKeysWithValues: DashboardLayout.factory.pages[0].placements.map {
            ($0.widgetID, DashboardGrid.frame(for: $0, in: screen))
        })

        #expect(frames[SpeedDashboardWidget.id] == CGRect(x: 0, y: 0, width: screen.width, height: unit * 2))
        #expect(frames[CadenceDashboardWidget.id] == CGRect(x: 0, y: unit * 2, width: screen.width, height: unit))
        #expect(frames[HeartRateDashboardWidget.id] == CGRect(x: 0, y: unit * 3, width: half, height: unit))
        #expect(frames[HRZonesDashboardWidget.id] == CGRect(x: half, y: unit * 3, width: half, height: unit))
        #expect(frames[PaceDashboardWidget.id] == CGRect(x: 0, y: unit * 4, width: half, height: unit))
        #expect(frames[DirectionsDashboardWidget.id] == CGRect(x: half, y: unit * 4, width: half, height: unit))
        #expect(frames[MapDashboardWidget.id] == CGRect(x: 0, y: unit * 5, width: screen.width, height: unit * 2))
    }

    @Test("A placement past the grid's edge is out of bounds")
    func outOfBounds() {
        let tooLow = WidgetPlacement(MapDashboardWidget.self, size: .twoByTwo, row: 6, column: 0)
        let tooWide = WidgetPlacement(CadenceDashboardWidget.self, size: .twoByOne, row: 0, column: 1)
        let negative = WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: -1, column: 0)

        #expect(DashboardLayoutValidator.violations(in: page(tooLow)) == [.outOfBounds(tooLow)])
        #expect(DashboardLayoutValidator.violations(in: page(tooWide)) == [.outOfBounds(tooWide)])
        #expect(DashboardLayoutValidator.violations(in: page(negative)) == [.outOfBounds(negative)])
    }

    /// Rows and columns come from a decoded file. Bounds checking must not add to them, or a
    /// corrupt value near `Int.max` traps inside `AppPreferences.init(from:)` on every launch.
    @Test("A corrupt row or column near Int.max is out of bounds, not a crash")
    func hugeRowDoesNotOverflow() {
        let row = WidgetPlacement(MapDashboardWidget.self, size: .twoByTwo, row: .max, column: 0)
        let column = WidgetPlacement(CadenceDashboardWidget.self, size: .twoByOne, row: 0, column: .max)
        #expect(DashboardLayoutValidator.violations(in: page(row)) == [.outOfBounds(row)])
        #expect(DashboardLayoutValidator.violations(in: page(column)) == [.outOfBounds(column)])
    }

    @Test("A size the widget doesn't support is rejected")
    func unsupportedSize() {
        let bigPace = WidgetPlacement(PaceDashboardWidget.self, size: .twoByTwo, row: 0, column: 0)
        #expect(DashboardLayoutValidator.violations(in: page(bigPace)) == [.unsupportedSize(bigPace)])
    }

    @Test("A widget id the catalog doesn't have is rejected")
    func unknownWidget() {
        let weather = WidgetPlacement(widgetID: "weather", size: .oneByOne, row: 0, column: 0)
        #expect(DashboardLayoutValidator.violations(in: page(weather)) == [.unknownWidget(weather)])
    }

    /// One bad placement costs that widget, not the rider's layout (#139 review): every kind of
    /// violation, each beside a placement that must survive. The earlier placement wins a conflict.
    @Test("Salvage drops only the placements that break a rule, keeping pages and their ids")
    func keepingValidPlacements() {
        let pace = WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 0, column: 0)
        let unknown = WidgetPlacement(widgetID: "weather", size: .oneByOne, row: 0, column: 1)
        let outOfBounds = WidgetPlacement(MapDashboardWidget.self, size: .twoByTwo, row: 6, column: 0)
        let unsupported = WidgetPlacement(HeartRateDashboardWidget.self, size: .twoByTwo, row: 2, column: 0)
        let overlapping = WidgetPlacement(CadenceDashboardWidget.self, size: .twoByOne, row: 0, column: 0)
        let duplicate = WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 5, column: 1)
        let hrZones = WidgetPlacement(HRZonesDashboardWidget.self, size: .oneByOne, row: 6, column: 1)
        let layout = DashboardLayout(pages: [
            page(pace, unknown, outOfBounds, unsupported, overlapping, duplicate, hrZones),
            page(unknown),
        ])

        let salvaged = layout.keepingValidPlacements()

        #expect(salvaged.pages.map(\.placements) == [[pace, hrZones], []])
        #expect(salvaged.pages.map(\.id) == layout.pages.map(\.id))
    }

    @Test("Removing a widget touches only the page it's on")
    func removingWidget() {
        let pace = WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 0, column: 0)
        let speed = WidgetPlacement(SpeedDashboardWidget.self, size: .twoByTwo, row: 2, column: 0)
        let layout = DashboardLayout(pages: [page(pace, speed), page(pace)])

        let removed = layout.removingWidget(PaceDashboardWidget.id, fromPage: layout.pages[0].id)

        #expect(removed.pages.map(\.placements) == [[speed], [pace]])
        #expect(removed.pages.map(\.id) == layout.pages.map(\.id))
    }

    @Test("Edit mode's blank page is appended once, however often it's asked for")
    func appendingBlankPage() {
        let pace = WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 0, column: 0)
        let layout = DashboardLayout(pages: [page(pace)])

        let blank = UUID()
        let once = layout.appendingBlankPage(id: blank)
        let twice = once.appendingBlankPage(id: UUID())

        #expect(once == DashboardLayout(pages: [layout.pages[0], DashboardPage(id: blank, placements: [])]))
        #expect(twice == once)
    }

    @Test("Pruning removes empty pages wherever they are, keeping the rest in order")
    func prunedEmptyPages() {
        let pace = WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 0, column: 0)
        let first = page(pace)
        let last = page(pace)
        let layout = DashboardLayout(pages: [page(), first, page(), last, page()])

        #expect(layout.prunedEmptyPages() == DashboardLayout(pages: [first, last]))
    }

    /// A layout needs a page, so removing every widget leaves one blank page — not zero pages,
    /// which would fail validation and silently restore the factory layout.
    @Test("Pruning a layout of only empty pages keeps one")
    func pruningKeepsOnePage() {
        let only = page()
        let pruned = DashboardLayout(pages: [only, page()]).prunedEmptyPages()

        #expect(pruned == DashboardLayout(pages: [only]))
        #expect(DashboardLayoutValidator.isValid(pruned))
    }

    /// One placement this build can't decode — a size a newer build added — must not throw the
    /// page, and with it the rider's whole layout, away (#141 review).
    @Test("A placement that doesn't decode is dropped, and the rest of the page kept")
    func undecodablePlacementIsDropped() throws {
        let json = Data(#"""
        {"pages":[{"placements":[
          {"widgetID":"speed","size":"threeByThree","row":0,"column":0},
          {"widgetID":"pace","size":"oneByOne","row":2,"column":0},
          {"widgetID":"cadence"}]}]}
        """#.utf8)

        let decoded = try JSONDecoder().decode(DashboardLayout.self, from: json)

        #expect(decoded.pages.map(\.placements) == [
            [WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 2, column: 0)],
        ])
    }

    /// The dashboard's `TabView` is keyed by page id.
    @Test("Two pages sharing an id make a layout invalid")
    func duplicatePageIDsAreInvalid() {
        let first = page(WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 0, column: 0))
        let copy = DashboardPage(id: first.id, placements: [WidgetPlacement(SpeedDashboardWidget.self, size: .oneByOne, row: 0, column: 0)])
        #expect(!DashboardLayoutValidator.isValid(DashboardLayout(pages: [first, copy])))
    }

    /// `.factory` mints page ids per launch, so a saved copy of it differs by `==`; matching it
    /// must ignore them, or that copy pins the rider to an old factory layout (#141 review).
    @Test("A layout is the factory one by its placements, whatever its page ids")
    func factoryMatchIgnoresPageIDs() {
        let copy = DashboardLayout(pages: DashboardLayout.factory.pages.map { DashboardPage(placements: $0.placements) })
        #expect(copy != .factory)
        #expect(copy.isFactory)
        #expect(!copy.removingWidget(SpeedDashboardWidget.id, fromPage: copy.pages[0].id).isFactory)
    }

    @Test("A page's id survives encoding")
    func pageIDRoundTrips() throws {
        let layout = DashboardLayout(pages: [
            page(WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 0, column: 0)),
        ])
        let decoded = try JSONDecoder().decode(DashboardLayout.self, from: JSONEncoder().encode(layout))
        #expect(decoded == layout)
    }

    /// #139 saved pages without an `id`. A synthesised decoder would throw on the missing key and
    /// lose the rider's layout.
    @Test("A page saved before pages had ids still decodes, each getting its own")
    func pageWithoutIDDecodes() throws {
        let json = Data(#"""
        {"pages":[
          {"placements":[{"widgetID":"pace","size":"oneByOne","row":0,"column":0}]},
          {"placements":[]}]}
        """#.utf8)

        let decoded = try JSONDecoder().decode(DashboardLayout.self, from: json)

        #expect(decoded.pages.map(\.placements) == [
            [WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 0, column: 0)], [],
        ])
        #expect(decoded.pages[0].id != decoded.pages[1].id)
    }

    @Test("Two widgets sharing a cell overlap")
    func overlap() {
        let speed = WidgetPlacement(SpeedDashboardWidget.self, size: .twoByTwo, row: 0, column: 0)
        let pace = WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 1, column: 1)
        #expect(DashboardLayoutValidator.violations(in: page(speed, pace)) == [.overlap(.init(row: 1, column: 1))])
    }

    @Test("A widget appears at most once per page")
    func duplicateWidget() {
        let left = WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 0, column: 0)
        let right = WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 0, column: 1)
        #expect(DashboardLayoutValidator.violations(in: page(left, right)) == [.duplicateWidget(PaceDashboardWidget.id)])
    }

    @Test("The same widget on two pages is fine, and empty cells are allowed")
    func sameWidgetAcrossPages() {
        let layout = DashboardLayout(pages: [
            page(WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 0, column: 0)),
            page(WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 6, column: 1)),
        ])
        #expect(DashboardLayoutValidator.isValid(layout))
    }

    @Test("A layout needs at least one page")
    func emptyLayoutIsInvalid() {
        #expect(!DashboardLayoutValidator.isValid(DashboardLayout(pages: [])))
    }

    /// S07 (#141) can drop pages while the rider is on one; the selection must stay on a real page.
    @Test("The visible page stays within the layout's pages")
    func visiblePageIsClamped() {
        withDependencies {
            $0.defaultFileStorage = .inMemory
        } operation: {
            var state = ActiveRideFeature.State()
            state.dashboardPage = 7
            #expect(state.visibleDashboardPage == DashboardLayout.factory.pages.count - 1)

            state.$preferences.withLock {
                $0.dashboardLayout = DashboardLayout(pages: [self.page()])
            }
            #expect(state.visibleDashboardPage == 0)

            state.dashboardPage = -1
            #expect(state.visibleDashboardPage == 0)
        }
    }
}
