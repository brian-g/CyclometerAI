import Testing
import CoreGraphics
@testable import Cyclometer

/// #494 — how many `ReadingColumn`s share a row: as many as the widest fits at its natural width,
/// so a long label wraps the row rather than itself.
@Suite("Reading columns")
struct ReadingColumnsTests {

    private func columns(_ width: CGFloat, _ widths: [CGFloat]) -> Int {
        ReadingColumns.columns(fitting: width, widths: widths, spacing: 12)
    }

    @Test func noReadingsNoColumns() {
        #expect(columns(320, []) == 0)
    }

    @Test func allFitSideBySide() {
        #expect(columns(320, [80, 60, 90]) == 3)
        // Exactly: 3 × 98 + 2 × 12 = 318.
        #expect(columns(318, [98, 98, 98]) == 3)
    }

    /// One wide label sets the width for all, so three become two, then one on the next line.
    @Test func theWidestWrapsTheRow() {
        #expect(columns(320, [60, 70, 120]) == 2)
        #expect(columns(317.9, [98, 98, 98]) == 2)
    }

    @Test func aReadingWiderThanTheRowStillGetsAColumn() {
        #expect(columns(100, [140]) == 1)
        #expect(columns(100, [140, 40]) == 1)
    }

    /// #548 — a cap holds the grid to that many, however many more would fit; it never adds columns.
    @Test func maxColumnsCapsTheGrid() {
        let widths: [CGFloat] = [60, 60, 60, 60, 60]
        #expect(ReadingColumns.columns(fitting: 400, widths: widths, spacing: 12, maxColumns: 2) == 2)
        #expect(ReadingColumns.columns(fitting: 100, widths: widths, spacing: 12, maxColumns: 2) == 1)
        #expect(ReadingColumns.columns(fitting: .infinity, widths: widths, spacing: 12, maxColumns: 2) == 2)
        #expect(ReadingColumns.columns(fitting: 400, widths: [60], spacing: 12, maxColumns: 2) == 1)
    }

    /// A stack measures a child's flexibility with an infinite width; `Int(_:)` would trap on it.
    @Test func anInfiniteWidthFitsThemAll() {
        #expect(columns(.infinity, [80, 60, 90]) == 3)
    }
}
