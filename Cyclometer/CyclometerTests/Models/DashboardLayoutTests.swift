import ComposableArchitecture
import CoreGraphics
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

    @Test("Removing unknown widgets keeps everything else")
    func removingUnknownWidgets() {
        let pace = WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 0, column: 0)
        let weather = WidgetPlacement(widgetID: "weather", size: .oneByOne, row: 0, column: 1)
        let layout = DashboardLayout(pages: [page(pace, weather), page(weather)])

        #expect(layout.removingUnknownWidgets() == DashboardLayout(pages: [page(pace), page()]))
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
