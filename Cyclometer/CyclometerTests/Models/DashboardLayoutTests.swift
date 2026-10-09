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

    @Test("A new widget goes in the first open spot in reading order")
    func firstOpenPlacementReadingOrder() {
        let pace = WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 0, column: 0)
        let cadence = WidgetPlacement(CadenceDashboardWidget.self, size: .twoByOne, row: 1, column: 0)
        let open = page(pace, cadence)

        #expect(open.firstOpenPlacement(widgetID: HeartRateDashboardWidget.id, size: .oneByOne)
            == WidgetPlacement(HeartRateDashboardWidget.self, size: .oneByOne, row: 0, column: 1))
        // Row 0 has a 1×1 gap, row 1 is full: a 2×2 needs rows 2–3.
        #expect(open.firstOpenPlacement(widgetID: SpeedDashboardWidget.id, size: .twoByTwo)
            == WidgetPlacement(SpeedDashboardWidget.self, size: .twoByTwo, row: 2, column: 0))
    }

    @Test("A widget already on the page, or a size the page has no room for, has no open spot")
    func firstOpenPlacementRefuses() {
        let pace = WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 0, column: 0)
        #expect(page(pace).firstOpenPlacement(widgetID: PaceDashboardWidget.id, size: .oneByOne) == nil)
        #expect(page(pace).firstOpenPlacement(widgetID: MapDashboardWidget.id, size: .twoByOne) == nil, "Map has no 2×1")

        // Every other row filled leaves only 1×1 and 2×1 gaps: no 2×2 fits, a 1×1 still does.
        let striped = DashboardPage(placements: [
            WidgetPlacement(SpeedDashboardWidget.self, size: .twoByOne, row: 0, column: 0),
            WidgetPlacement(CadenceDashboardWidget.self, size: .twoByOne, row: 2, column: 0),
            WidgetPlacement(DirectionsDashboardWidget.self, size: .twoByOne, row: 4, column: 0),
            WidgetPlacement(HeartRateDashboardWidget.self, size: .oneByOne, row: 6, column: 0),
        ])
        #expect(striped.firstOpenPlacement(widgetID: MapDashboardWidget.id, size: .twoByTwo) == nil)
        #expect(striped.firstOpenPlacement(widgetID: PaceDashboardWidget.id, size: .oneByOne)
            == WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 1, column: 0))
    }

    @Test("Adding a widget touches only its page, and does nothing when there's no room")
    func addingWidget() {
        let pace = WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 0, column: 0)
        let layout = DashboardLayout(pages: [page(pace), page(pace)])

        let added = layout.addingWidget(HeartRateDashboardWidget.id, size: .oneByOne, toPage: layout.pages[1].id)
        #expect(added.pages.map(\.placements) == [
            [pace],
            [pace, WidgetPlacement(HeartRateDashboardWidget.self, size: .oneByOne, row: 0, column: 1)],
        ])
        #expect(added.pages.map(\.id) == layout.pages.map(\.id))
        #expect(layout.addingWidget(PaceDashboardWidget.id, size: .oneByOne, toPage: layout.pages[0].id) == layout)
    }

    // ── Adding at a tapped empty cell (#368) ──────────────────────────────────

    private func cell(_ row: Int, _ column: Int) -> DashboardGrid.Cell {
        DashboardGrid.Cell(row: row, column: column)
    }

    @Test("Empty cells are the ones no placement covers, in reading order")
    func emptyCells() {
        let speed = WidgetPlacement(SpeedDashboardWidget.self, size: .twoByTwo, row: 0, column: 0)
        let pace = WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 2, column: 1)
        let cadence = WidgetPlacement(CadenceDashboardWidget.self, size: .twoByOne, row: 3, column: 0)
        let directions = WidgetPlacement(DirectionsDashboardWidget.self, size: .twoByOne, row: 4, column: 0)
        let map = WidgetPlacement(MapDashboardWidget.self, size: .twoByTwo, row: 5, column: 0)

        #expect(page(speed, pace, cadence, directions, map).emptyCells == [cell(2, 0)])
        #expect(page().emptyCells.count == DashboardGrid.rows * DashboardGrid.columns)
        #expect(page(speed).emptyCells.first == cell(2, 0))
    }

    /// The tapped cell is the widget's top-left; nothing shifts to fit (#368).
    @Test("A size fits at a cell only with that cell as its top-left, on the grid, over empty cells")
    func fitsAtCell() {
        let empty = page()
        #expect(empty.fits(.oneByOne, at: cell(6, 1)))
        #expect(empty.fits(.twoByOne, at: cell(0, 0)))
        #expect(!empty.fits(.twoByOne, at: cell(0, 1)), "Right column: a 2×1 would leave the grid")
        #expect(empty.fits(.twoByTwo, at: cell(5, 0)))
        #expect(!empty.fits(.twoByTwo, at: cell(6, 0)), "Last row: a 2×2 would leave the grid")

        let pace = WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 1, column: 1)
        #expect(page(pace).fits(.oneByOne, at: cell(1, 0)))
        #expect(!page(pace).fits(.twoByOne, at: cell(1, 0)), "Its neighbour is taken")
        #expect(!page(pace).fits(.twoByTwo, at: cell(0, 0)), "Its block overlaps Pace")
        #expect(!page(pace).fits(.oneByOne, at: cell(1, 1)), "The cell itself is taken")
    }

    @Test("A widget placed at a cell anchors there, under the layout rules; no cell means the first open spot")
    func openPlacementAtCell() {
        let pace = WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 0, column: 0)
        let open = page(pace)

        #expect(open.openPlacement(widgetID: HeartRateDashboardWidget.id, size: .oneByOne, at: cell(3, 1))
            == WidgetPlacement(HeartRateDashboardWidget.self, size: .oneByOne, row: 3, column: 1))
        #expect(open.openPlacement(widgetID: SpeedDashboardWidget.id, size: .twoByTwo, at: cell(4, 0))
            == WidgetPlacement(SpeedDashboardWidget.self, size: .twoByTwo, row: 4, column: 0))
        #expect(open.openPlacement(widgetID: PaceDashboardWidget.id, size: .oneByOne, at: cell(3, 1)) == nil, "Already on the page")
        #expect(open.openPlacement(widgetID: MapDashboardWidget.id, size: .oneByOne, at: cell(3, 1)) == nil, "Map has no 1×1")
        #expect(open.openPlacement(widgetID: CadenceDashboardWidget.id, size: .twoByOne, at: cell(3, 1)) == nil, "Not shifted left to fit")
        #expect(open.openPlacement(widgetID: HeartRateDashboardWidget.id, size: .oneByOne, at: nil)
            == open.firstOpenPlacement(widgetID: HeartRateDashboardWidget.id, size: .oneByOne))
    }

    @Test("Adding at a cell touches only its page, and does nothing when it doesn't fit there")
    func addingWidgetAtCell() {
        let pace = WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 0, column: 0)
        let layout = DashboardLayout(pages: [page(pace), page(pace)])

        let added = layout.addingWidget(HeartRateDashboardWidget.id, size: .oneByOne, toPage: layout.pages[1].id, at: cell(5, 1))
        #expect(added.pages.map(\.placements) == [
            [pace],
            [pace, WidgetPlacement(HeartRateDashboardWidget.self, size: .oneByOne, row: 5, column: 1)],
        ])
        #expect(added.pages.map(\.id) == layout.pages.map(\.id))
        #expect(layout.addingWidget(SpeedDashboardWidget.id, size: .twoByOne, toPage: layout.pages[0].id, at: cell(0, 1)) == layout)
    }

    // ── Moving a widget (#367) ────────────────────────────────────────────────

    @Test("A widget moves into a spot that's empty once it has left, its own cells included")
    func movingToEmptySpot() {
        let pace = WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 0, column: 0)
        let speed = WidgetPlacement(SpeedDashboardWidget.self, size: .twoByTwo, row: 2, column: 0)
        let start = page(pace, speed)

        #expect(start.moving(PaceDashboardWidget.id, to: cell(6, 1))?.placements == [
            WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 6, column: 1), speed,
        ])
        // Rows 3–4: row 3 is Speed's own.
        #expect(start.moving(SpeedDashboardWidget.id, to: cell(3, 0))?.placements == [
            pace, WidgetPlacement(SpeedDashboardWidget.self, size: .twoByTwo, row: 3, column: 0),
        ])
    }

    @Test("A widget dropped on a same-size widget's top-left swaps with it, at every size")
    func movingSwapsSameSize() {
        let pace = WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 0, column: 0)
        let heartRate = WidgetPlacement(HeartRateDashboardWidget.self, size: .oneByOne, row: 4, column: 1)
        let cadence = WidgetPlacement(CadenceDashboardWidget.self, size: .twoByOne, row: 1, column: 0)
        let directions = WidgetPlacement(DirectionsDashboardWidget.self, size: .twoByOne, row: 6, column: 0)
        let speed = WidgetPlacement(SpeedDashboardWidget.self, size: .twoByTwo, row: 2, column: 0)
        let start = page(pace, heartRate, cadence, directions, speed)

        func at(_ placement: WidgetPlacement, _ row: Int, _ column: Int) -> WidgetPlacement {
            WidgetPlacement(widgetID: placement.widgetID, size: placement.size, row: row, column: column)
        }
        #expect(start.moving(PaceDashboardWidget.id, to: cell(4, 1))?.placements
            == [at(pace, 4, 1), at(heartRate, 0, 0), cadence, directions, speed])
        #expect(start.moving(DirectionsDashboardWidget.id, to: cell(1, 0))?.placements
            == [pace, heartRate, at(cadence, 6, 0), at(directions, 1, 0), speed])

        let map = WidgetPlacement(MapDashboardWidget.self, size: .twoByTwo, row: 5, column: 0)
        #expect(page(speed, map).moving(MapDashboardWidget.id, to: cell(2, 0))?.placements
            == [at(speed, 5, 0), at(map, 2, 0)])
    }

    @Test("A drop onto a different size, an out-of-line widget, off the grid, or its own spot is refused")
    func movingRefuses() {
        let pace = WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 0, column: 0)
        let heartRate = WidgetPlacement(HeartRateDashboardWidget.self, size: .oneByOne, row: 0, column: 1)
        let cadence = WidgetPlacement(CadenceDashboardWidget.self, size: .twoByOne, row: 1, column: 0)
        let speed = WidgetPlacement(SpeedDashboardWidget.self, size: .twoByTwo, row: 2, column: 0)
        let map = WidgetPlacement(MapDashboardWidget.self, size: .twoByTwo, row: 4, column: 0)
        let start = page(pace, heartRate, cadence, speed, map)

        #expect(start.moving(SpeedDashboardWidget.id, to: cell(0, 0)) == nil, "A 2×2 onto two 1×1s and a 2×1")
        #expect(start.moving(PaceDashboardWidget.id, to: cell(1, 0)) == nil, "A 1×1 onto a 2×1")
        #expect(start.moving(SpeedDashboardWidget.id, to: cell(3, 0)) == nil, "A 2×2 half onto another 2×2")
        #expect(start.moving(MapDashboardWidget.id, to: cell(6, 0)) == nil, "Off the bottom")
        #expect(start.moving(PaceDashboardWidget.id, to: cell(6, -1)) == nil, "Off the left")
        #expect(start.moving(CadenceDashboardWidget.id, to: cell(6, 1)) == nil, "A 2×1 from the right column")
        #expect(start.moving(PaceDashboardWidget.id, to: cell(0, 0)) == nil, "Its own spot")
        #expect(start.moving(DirectionsDashboardWidget.id, to: cell(6, 0)) == nil, "Not on the page")
    }

    @Test("Moving touches only its page, and leaves the layout as it was when refused")
    func movingWidget() {
        let pace = WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 0, column: 0)
        let cadence = WidgetPlacement(CadenceDashboardWidget.self, size: .twoByOne, row: 1, column: 0)
        let layout = DashboardLayout(pages: [page(pace, cadence), page(pace, cadence)])

        let moved = layout.movingWidget(PaceDashboardWidget.id, onPage: layout.pages[1].id, to: cell(0, 1))
        #expect(moved.pages.map(\.placements) == [
            [pace, cadence],
            [WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 0, column: 1), cadence],
        ])
        #expect(moved.pages.map(\.id) == layout.pages.map(\.id))
        #expect(layout.movingWidget(PaceDashboardWidget.id, onPage: layout.pages[0].id, to: cell(1, 0)) == layout)
    }

    /// VoiceOver's Move actions (#367) can't drag past a widget in the way, so they jump it.
    @Test("A Move action goes to the nearest spot that way the move accepts, jumping what's in the way")
    func moveTarget() {
        let pace = WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 3, column: 0)
        let heartRate = WidgetPlacement(HeartRateDashboardWidget.self, size: .oneByOne, row: 3, column: 1)
        let cadence = WidgetPlacement(CadenceDashboardWidget.self, size: .twoByOne, row: 2, column: 0)
        let speed = WidgetPlacement(SpeedDashboardWidget.self, size: .twoByTwo, row: 5, column: 0)
        let start = page(pace, heartRate, cadence, speed)

        #expect(start.moveTarget(for: PaceDashboardWidget.id, .up) == cell(1, 0), "Jumps Cadence")
        #expect(start.moveTarget(for: PaceDashboardWidget.id, .right) == cell(3, 1), "Swaps with Heart Rate")
        #expect(start.moveTarget(for: PaceDashboardWidget.id, .down) == cell(4, 0))
        #expect(start.moveTarget(for: PaceDashboardWidget.id, .left) == nil, "Already at the edge")
        #expect(start.moveTarget(for: SpeedDashboardWidget.id, .down) == nil, "Already at the bottom")
        #expect(start.moveTarget(for: SpeedDashboardWidget.id, .up) == cell(4, 0), "One row: its own row 5 counts as free")
        #expect(start.moveTarget(for: CadenceDashboardWidget.id, .left) == nil, "A full-width widget can't go sideways")
        #expect(start.moveTarget(for: CadenceDashboardWidget.id, .right) == nil)
        #expect(start.moveTarget(for: DirectionsDashboardWidget.id, .up) == nil, "Not on the page")
    }

    @Test("A drop lands on the cell nearest the widget's top-left, unclamped, and needs a sized grid")
    func cellNearestOrigin() {
        let grid = CGSize(width: 200, height: 700)
        #expect(DashboardGrid.cell(nearest: CGPoint(x: 49, y: 149), in: grid) == cell(1, 0))
        #expect(DashboardGrid.cell(nearest: CGPoint(x: 51, y: 151), in: grid) == cell(2, 1))
        #expect(DashboardGrid.cell(nearest: CGPoint(x: -60, y: 690), in: grid) == cell(7, -1), "Off the grid stays off")
        #expect(DashboardGrid.cell(nearest: .zero, in: .zero) == nil)
    }

    @Test("An empty page goes right after the page it's added from")
    func insertingBlankPage() {
        let pace = WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 0, column: 0)
        let layout = DashboardLayout(pages: [page(pace), page(pace)])
        let blank = UUID()

        let inserted = layout.insertingBlankPage(id: blank, after: layout.pages[0].id)
        #expect(inserted.pages.map(\.id) == [layout.pages[0].id, blank, layout.pages[1].id])
        #expect(inserted.pages[1].placements.isEmpty)
        #expect(layout.insertingBlankPage(id: blank, after: UUID()) == layout)
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
