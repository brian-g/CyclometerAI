import CoreGraphics

/// A widget the rider can place on the dashboard (UX.md §S05 "Widget Details").
///
/// W7 Radar is not one: it is the full-height lane beside the grid on every page (PRD §8.2,
/// UX.md §S06), so it can't be placed, moved or removed. Widgets not built yet (W2, W3, W6,
/// W10) join this list when they land (#140, #150).
enum WidgetKind: String, Codable, CaseIterable, Equatable {
    case speed
    case cadence
    case heartRate
    case hrZones
    case pace
    case directions
    case map

    /// The sizes this widget has a layout for. The validator rejects any other, and S08 (#142)
    /// filters its picker by them.
    var supportedSizes: [WidgetSize] {
        switch self {
        case .speed: [.oneByOne, .twoByOne, .twoByTwo]
        case .cadence, .directions: [.oneByOne, .twoByOne]
        case .heartRate, .hrZones, .pace: [.oneByOne]
        case .map: [.twoByTwo]
        }
    }
}

/// One widget at one position. `row` and `column` are its top-left cell, 0-based.
struct WidgetPlacement: Codable, Equatable {
    var kind: WidgetKind
    var size: WidgetSize
    var row: Int
    var column: Int

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
        case outOfBounds(WidgetPlacement)
        case unsupportedSize(WidgetPlacement)
        case overlap(DashboardGrid.Cell)
        /// Each kind at most once per page; the same kind may appear on other pages.
        case duplicateKind(WidgetKind)
    }

    static func violations(in page: DashboardPage) -> [Violation] {
        var violations: [Violation] = []
        var occupied: Set<DashboardGrid.Cell> = []
        var kinds: Set<WidgetKind> = []
        for placement in page.placements {
            if !placement.kind.supportedSizes.contains(placement.size) {
                violations.append(.unsupportedSize(placement))
            }
            let inBounds = placement.row >= 0 && placement.column >= 0
                && placement.row + placement.size.rows <= DashboardGrid.rows
                && placement.column + placement.size.columns <= DashboardGrid.columns
            if !inBounds {
                violations.append(.outOfBounds(placement))
            }
            for cell in placement.cells where !occupied.insert(cell).inserted {
                violations.append(.overlap(cell))
            }
            if !kinds.insert(placement.kind).inserted {
                violations.append(.duplicateKind(placement.kind))
            }
        }
        return violations
    }

    static func isValid(_ layout: DashboardLayout) -> Bool {
        !layout.pages.isEmpty && layout.pages.allSatisfy { violations(in: $0).isEmpty }
    }
}

extension DashboardLayout {
    /// What a new rider sees. Page 1 is S05.4. Pages 2–3 are a temporary showcase that puts every
    /// widget on screen at every size it supports, until the spec settles page 2 (UX.md §S05
    /// "Multiple pages": TBD).
    static let factory = DashboardLayout(pages: [
        DashboardPage(placements: [
            WidgetPlacement(kind: .speed, size: .twoByTwo, row: 0, column: 0),
            WidgetPlacement(kind: .cadence, size: .twoByOne, row: 2, column: 0),
            WidgetPlacement(kind: .heartRate, size: .oneByOne, row: 3, column: 0),
            WidgetPlacement(kind: .hrZones, size: .oneByOne, row: 3, column: 1),
            WidgetPlacement(kind: .pace, size: .oneByOne, row: 4, column: 0),
            WidgetPlacement(kind: .directions, size: .oneByOne, row: 4, column: 1),
            // Bleeds behind the floating toolbar to the screen bottom.
            WidgetPlacement(kind: .map, size: .twoByTwo, row: 5, column: 0),
        ]),
        DashboardPage(placements: [
            // Bleeds up behind the Dynamic Island.
            WidgetPlacement(kind: .map, size: .twoByTwo, row: 0, column: 0),
            WidgetPlacement(kind: .speed, size: .twoByOne, row: 2, column: 0),
            WidgetPlacement(kind: .directions, size: .twoByOne, row: 3, column: 0),
            WidgetPlacement(kind: .cadence, size: .oneByOne, row: 4, column: 0),
            WidgetPlacement(kind: .heartRate, size: .oneByOne, row: 4, column: 1),
            WidgetPlacement(kind: .hrZones, size: .oneByOne, row: 5, column: 0),
            WidgetPlacement(kind: .pace, size: .oneByOne, row: 5, column: 1),
            // Row 7 left empty: blank cells, and no widget stretched into them.
        ]),
        DashboardPage(placements: [
            WidgetPlacement(kind: .speed, size: .oneByOne, row: 0, column: 0),
        ]),
    ])
}
