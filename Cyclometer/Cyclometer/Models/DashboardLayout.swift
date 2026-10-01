import CoreGraphics

/// One widget at one position. `row` and `column` are its top-left cell, 0-based.
///
/// The widget is named by its `DashboardWidget.id`, a string rather than an enum case, so a
/// saved layout naming a widget this build doesn't have still decodes; that placement is dropped
/// (`removingUnknownWidgets`) and the rest kept.
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

    /// Every grid cell this placement covers, as (row, column).
    var cells: [DashboardGrid.Cell] {
        (row..<row + size.rows).flatMap { r in
            (column..<column + size.columns).map { DashboardGrid.Cell(row: r, column: $0) }
        }
    }
}

/// One swipeable page of the dashboard. Cells no placement covers stay blank (UX.md §S05
/// "Empty cells"), which is why placements are positional rather than an ordered list.
struct DashboardPage: Codable, Equatable {
    var placements: [WidgetPlacement]
}

/// The rider's dashboard: its pages, in swipe order. Persisted in `AppPreferences`.
struct DashboardLayout: Codable, Equatable {
    var pages: [DashboardPage]

    /// This layout without placements naming a widget the catalog doesn't have — one from a newer
    /// build, or one since removed. Losing that widget beats losing the rider's whole layout.
    func removingUnknownWidgets() -> DashboardLayout {
        DashboardLayout(pages: pages.map { page in
            DashboardPage(placements: page.placements.filter { DashboardWidgetCatalog.widget(id: $0.widgetID) != nil })
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

    /// Where `placement` sits in a grid of `size`. Rows are `height / 7` and columns `width / 2`
    /// whatever else is on the page, so a widget is never stretched into leftover space (#82).
    static func frame(for placement: WidgetPlacement, in size: CGSize) -> CGRect {
        let columnWidth = size.width / CGFloat(columns)
        let rowHeight = size.height / CGFloat(rows)
        return CGRect(
            x: CGFloat(placement.column) * columnWidth,
            y: CGFloat(placement.row) * rowHeight,
            width: CGFloat(placement.size.columns) * columnWidth,
            height: CGFloat(placement.size.rows) * rowHeight
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

    static func isValid(_ layout: DashboardLayout) -> Bool {
        !layout.pages.isEmpty && layout.pages.allSatisfy { violations(in: $0).isEmpty }
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
