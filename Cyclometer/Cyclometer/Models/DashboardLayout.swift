import CoreGraphics
import Foundation

/// One widget at one position. `row` and `column` are its top-left cell, 0-based.
///
/// The widget is named by its `DashboardWidget.id`, a string rather than an enum case, so a
/// saved layout naming a widget this build doesn't have still decodes; that placement is dropped
/// (`DashboardLayout.keepingValidPlacements`) and the rest kept.
struct WidgetPlacement: Codable, Equatable {
    var widgetID: String
    var size: WidgetSize
    var row: Int
    var column: Int

    init(widgetID: String, size: WidgetSize, row: Int, column: Int) {
        self.widgetID = widgetID
        self.size = size
        self.row = row
        self.column = column
    }

    init(_ widget: any DashboardWidget.Type, size: WidgetSize, row: Int, column: Int) {
        self.init(widgetID: widget.id, size: size, row: row, column: column)
    }

    /// Its top-left cell.
    var cell: DashboardGrid.Cell { DashboardGrid.Cell(row: row, column: column) }

    /// Every grid cell this placement covers, as (row, column).
    var cells: [DashboardGrid.Cell] { DashboardGrid.cells(at: cell, size: size) }
}

/// One swipeable page of the dashboard. Cells no placement covers stay blank (UX.md §S05
/// "Empty cells"), which is why placements are positional rather than an ordered list.
///
/// `id` keeps a page's view attached to the page, not to its index, when S07 (#141) appends or
/// prunes pages around it. It is saved, so it also survives a relaunch.
struct DashboardPage: Codable, Equatable, Identifiable {
    var id = UUID()
    var placements: [WidgetPlacement]
}

extension DashboardPage {
    /// By hand, because #139 saved pages without an `id`, and the synthesised decoder throws on a
    /// missing key — which would reset the whole layout. Any field added to these types later must
    /// be optional or decoded the same way.
    ///
    /// Each placement decodes on its own, so one this build can't read — a `WidgetSize` a newer
    /// build added, say — costs that widget, not the page and with it the rider's whole layout.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        placements = try container.decode([LossyPlacement].self, forKey: .placements).compactMap(\.placement)
    }

    private struct LossyPlacement: Decodable {
        let placement: WidgetPlacement?

        init(from decoder: any Decoder) throws {
            placement = try? WidgetPlacement(from: decoder)
        }
    }

    /// Where S08 (#142) would put `widgetID` at `size`: the first spot in reading order that breaks
    /// no layout rule. `nil` when there's none — the widget is already on this page, or no gap is
    /// big enough — which is when the picker dims that entry.
    func firstOpenPlacement(widgetID: String, size: WidgetSize) -> WidgetPlacement? {
        for row in 0...(DashboardGrid.rows - size.rows) {
            for column in 0...(DashboardGrid.columns - size.columns) {
                let cell = DashboardGrid.Cell(row: row, column: column)
                if let placement = openPlacement(widgetID: widgetID, size: size, at: cell) { return placement }
            }
        }
        return nil
    }

    /// Where S08 would put `widgetID` at `size`: with its top-left at `cell` when the rider opened
    /// it from that empty cell (#368), else `firstOpenPlacement`. Anchored, never shifted to fit,
    /// so the widget lands where the rider tapped. `nil` when that breaks a layout rule.
    func openPlacement(widgetID: String, size: WidgetSize, at cell: DashboardGrid.Cell?) -> WidgetPlacement? {
        guard let cell else { return firstOpenPlacement(widgetID: widgetID, size: size) }
        let candidate = WidgetPlacement(widgetID: widgetID, size: size, row: cell.row, column: cell.column)
        let page = DashboardPage(placements: placements + [candidate])
        return DashboardLayoutValidator.violations(in: page).isEmpty ? candidate : nil
    }

    /// Whether a widget of `size` with its top-left at `cell` stays on the grid and covers only
    /// empty cells, whichever widget it is. S08 opened from `cell` (#368) lists only these sizes.
    func fits(_ size: WidgetSize, at cell: DashboardGrid.Cell) -> Bool {
        // A cell off the grid is never among `emptyCells`, so this is the bounds check too.
        Set(emptyCells).isSuperset(of: DashboardGrid.cells(at: cell, size: size))
    }

    /// The cells no placement covers, in reading order: S07 edit mode's add-here slots (#368).
    var emptyCells: [DashboardGrid.Cell] {
        let occupied = Set(placements.flatMap(\.cells))
        return (0..<DashboardGrid.rows).flatMap { row in
            (0..<DashboardGrid.columns).map { DashboardGrid.Cell(row: row, column: $0) }
        }
        .filter { !occupied.contains($0) }
    }
}

/// The rider's dashboard: its pages, in swipe order. Persisted in `AppPreferences`.
struct DashboardLayout: Codable, Equatable {
    var pages: [DashboardPage]

    /// This layout with each page keeping only the placements that break no rule
    /// (`DashboardLayoutValidator`), the earlier one winning a conflict. A widget a newer build
    /// added, one since removed, or an overlap from a corrupt file costs that widget, not the
    /// rider's whole layout.
    func keepingValidPlacements() -> DashboardLayout {
        mapPages { page in
            page.placements = page.placements.reduce(into: []) { kept, placement in
                let candidate = DashboardPage(placements: kept + [placement])
                if DashboardLayoutValidator.violations(in: candidate).isEmpty { kept.append(placement) }
            }
        }
    }

    /// This layout without `widgetID` on the page `pageID` (S07 remove).
    func removingWidget(_ widgetID: String, fromPage pageID: DashboardPage.ID) -> DashboardLayout {
        mapPages { page in
            if page.id == pageID { page.placements.removeAll { $0.widgetID == widgetID } }
        }
    }

    /// This layout with `widgetID` at `size` on the page `pageID` (S08, #142): at `cell` when S08 was
    /// opened from that empty cell (#368), else in the first open spot. Unchanged when it doesn't
    /// fit there (`DashboardPage.openPlacement`).
    func addingWidget(
        _ widgetID: String, size: WidgetSize, toPage pageID: DashboardPage.ID, at cell: DashboardGrid.Cell? = nil
    ) -> DashboardLayout {
        mapPages { page in
            guard page.id == pageID, let placement = page.openPlacement(widgetID: widgetID, size: size, at: cell) else { return }
            page.placements.append(placement)
        }
    }

    /// This layout with a blank page right after the page `pageID` (S08's "Empty page", #142). Done
    /// prunes it if the rider leaves it empty.
    func insertingBlankPage(id: DashboardPage.ID, after pageID: DashboardPage.ID) -> DashboardLayout {
        guard let index = pages.firstIndex(where: { $0.id == pageID }) else { return self }
        var pages = pages
        pages.insert(DashboardPage(id: id, placements: []), at: index + 1)
        return DashboardLayout(pages: pages)
    }

    /// This layout without its empty pages (UX.md §S07: "Empty pages are removed on exit"). Keeps
    /// one when every page is empty, since a layout needs a page; a rider who removed every widget
    /// gets a blank dashboard, not the factory one.
    /// Whether this is the factory layout: the same widgets in the same places on the same pages.
    /// Page ids don't count — `.factory` mints new ones each launch, so a saved copy of it never
    /// matches by `==`, and would pin the rider to it after the factory changes (#141 review).
    var isFactory: Bool {
        pages.map(\.placements) == Self.factory.pages.map(\.placements)
    }

    func prunedEmptyPages() -> DashboardLayout {
        let filled = pages.filter { !$0.placements.isEmpty }
        return DashboardLayout(pages: filled.isEmpty ? Array(pages.prefix(1)) : filled)
    }

    private func mapPages(_ transform: (inout DashboardPage) -> Void) -> DashboardLayout {
        DashboardLayout(pages: pages.map { page in
            var page = page
            transform(&page)
            return page
        })
    }
}

/// The dashboard's fixed 2-column × 7-row canvas (UX.md §S05 "Grid").
enum DashboardGrid {
    static let columns = 2
    static let rows = 7

    struct Cell: Hashable {
        var row: Int
        var column: Int
    }

    /// Every cell a `size` widget with its top-left at `cell` covers.
    static func cells(at cell: Cell, size: WidgetSize) -> [Cell] {
        (cell.row..<cell.row + size.rows).flatMap { row in
            (cell.column..<cell.column + size.columns).map { Cell(row: row, column: $0) }
        }
    }

    /// Where `placement` sits in a grid of `size`. Rows are `height / 7` and columns `width / 2`
    /// whatever else is on the page, so a widget is never stretched into leftover space (#82).
    static func frame(for placement: WidgetPlacement, in size: CGSize) -> CGRect {
        frame(at: placement.cell, size: placement.size, in: size)
    }

    /// Where a `widgetSize` view with its top-left at `cell` sits in a grid of `size` — a widget, or
    /// S07's empty-cell slot (#368), which has no widget to place.
    static func frame(at cell: Cell, size widgetSize: WidgetSize, in size: CGSize) -> CGRect {
        let columnWidth = size.width / CGFloat(columns)
        let rowHeight = size.height / CGFloat(rows)
        return CGRect(
            x: CGFloat(cell.column) * columnWidth,
            y: CGFloat(cell.row) * rowHeight,
            width: CGFloat(widgetSize.columns) * columnWidth,
            height: CGFloat(widgetSize.rows) * rowHeight
        )
    }
}

/// The rules every page must satisfy (UX.md §S05 "Customisation"). S07/S08 check each change
/// against these before applying it.
enum DashboardLayoutValidator {
    enum Violation: Equatable {
        case unknownWidget(WidgetPlacement)
        case outOfBounds(WidgetPlacement)
        /// A size the widget doesn't list in its `supportedSizes`.
        case unsupportedSize(WidgetPlacement)
        case overlap(DashboardGrid.Cell)
        /// Each widget at most once per page; the same widget may appear on other pages.
        case duplicateWidget(String)
    }

    static func violations(in page: DashboardPage) -> [Violation] {
        var violations: [Violation] = []
        var occupied: Set<DashboardGrid.Cell> = []
        var widgetIDs: Set<String> = []
        for placement in page.placements {
            if !widgetIDs.insert(placement.widgetID).inserted {
                violations.append(.duplicateWidget(placement.widgetID))
            }
            if let widget = DashboardWidgetCatalog.widget(id: placement.widgetID) {
                if !widget.supportedSizes.contains(placement.size) {
                    violations.append(.unsupportedSize(placement))
                }
            } else {
                violations.append(.unknownWidget(placement))
            }
            // Subtracts rather than adds: these come from a decoded file, and `row + rows` with a
            // corrupt `row` near `Int.max` would trap where `try?` can't catch it.
            let inBounds = placement.row >= 0 && placement.column >= 0
                && placement.row <= DashboardGrid.rows - placement.size.rows
                && placement.column <= DashboardGrid.columns - placement.size.columns
            guard inBounds else {
                violations.append(.outOfBounds(placement))
                continue
            }
            for cell in placement.cells where !occupied.insert(cell).inserted {
                violations.append(.overlap(cell))
            }
        }
        return violations
    }

    /// At least one page, page ids unique — the dashboard's `TabView` is keyed by them — and every
    /// page free of violations.
    static func isValid(_ layout: DashboardLayout) -> Bool {
        !layout.pages.isEmpty
            && Set(layout.pages.map(\.id)).count == layout.pages.count
            && layout.pages.allSatisfy { violations(in: $0).isEmpty }
    }
}

extension DashboardLayout {
    /// What a new rider sees. Page 1 is the dashboard as built before #139, which differs from
    /// UX.md's S05.4 table (no radar cell; Cadence 2×1 on row 3). Pages 2–3 are a
    /// temporary showcase that puts every widget on screen at every size it supports, until the
    /// spec settles page 2 (UX.md §S05 "Multiple pages": TBD).
    static let factory = DashboardLayout(pages: [
        DashboardPage(placements: [
            WidgetPlacement(SpeedDashboardWidget.self, size: .twoByTwo, row: 0, column: 0),
            WidgetPlacement(CadenceDashboardWidget.self, size: .twoByOne, row: 2, column: 0),
            WidgetPlacement(HeartRateDashboardWidget.self, size: .oneByOne, row: 3, column: 0),
            WidgetPlacement(HRZonesDashboardWidget.self, size: .oneByOne, row: 3, column: 1),
            WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 4, column: 0),
            WidgetPlacement(DirectionsDashboardWidget.self, size: .oneByOne, row: 4, column: 1),
            // Bleeds behind the floating toolbar to the screen bottom.
            WidgetPlacement(MapDashboardWidget.self, size: .twoByTwo, row: 5, column: 0),
        ]),
        DashboardPage(placements: [
            // Bleeds up behind the Dynamic Island.
            WidgetPlacement(MapDashboardWidget.self, size: .twoByTwo, row: 0, column: 0),
            WidgetPlacement(SpeedDashboardWidget.self, size: .twoByOne, row: 2, column: 0),
            WidgetPlacement(DirectionsDashboardWidget.self, size: .twoByOne, row: 3, column: 0),
            WidgetPlacement(CadenceDashboardWidget.self, size: .oneByOne, row: 4, column: 0),
            WidgetPlacement(HeartRateDashboardWidget.self, size: .oneByOne, row: 4, column: 1),
            WidgetPlacement(HRZonesDashboardWidget.self, size: .oneByOne, row: 5, column: 0),
            WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 5, column: 1),
            // Row 7 left empty: blank cells, and no widget stretched into them.
        ]),
        DashboardPage(placements: [
            WidgetPlacement(SpeedDashboardWidget.self, size: .oneByOne, row: 0, column: 0),
        ]),
    ])
}
