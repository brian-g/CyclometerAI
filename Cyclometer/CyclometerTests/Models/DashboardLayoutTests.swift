import CoreGraphics
import Testing
@testable import Cyclometer

struct DashboardLayoutTests {
    private func page(_ placements: WidgetPlacement...) -> DashboardPage {
        DashboardPage(placements: placements)
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
    func factoryCoversEveryKindAndSize() {
        let placed = Set(DashboardLayout.factory.pages.flatMap(\.placements).map { "\($0.kind)-\($0.size)" })
        for kind in WidgetKind.allCases {
            for size in kind.supportedSizes {
                #expect(placed.contains("\(kind)-\(size)"), "\(kind) \(size) is never shown")
            }
        }
    }

    /// Page 1 must land exactly where the hand-built S05.4 grid put each widget: rows of
    /// height/7, columns of width/2.
    @Test("Factory page 1 lays out as the S05.4 grid did")
    func factoryPageOneGeometry() {
        let screen = CGSize(width: 402, height: 874)
        let unit = screen.height / 7
        let half = screen.width / 2
        let frames = Dictionary(uniqueKeysWithValues: DashboardLayout.factory.pages[0].placements.map {
            ($0.kind, DashboardGrid.frame(for: $0, in: screen))
        })

        #expect(frames[.speed] == CGRect(x: 0, y: 0, width: screen.width, height: unit * 2))
        #expect(frames[.cadence] == CGRect(x: 0, y: unit * 2, width: screen.width, height: unit))
        #expect(frames[.heartRate] == CGRect(x: 0, y: unit * 3, width: half, height: unit))
        #expect(frames[.hrZones] == CGRect(x: half, y: unit * 3, width: half, height: unit))
        #expect(frames[.pace] == CGRect(x: 0, y: unit * 4, width: half, height: unit))
        #expect(frames[.directions] == CGRect(x: half, y: unit * 4, width: half, height: unit))
        #expect(frames[.map] == CGRect(x: 0, y: unit * 5, width: screen.width, height: unit * 2))
    }

    @Test("A placement past the grid's edge is out of bounds")
    func outOfBounds() {
        let tooLow = WidgetPlacement(kind: .map, size: .twoByTwo, row: 6, column: 0)
        let tooWide = WidgetPlacement(kind: .cadence, size: .twoByOne, row: 0, column: 1)
        let negative = WidgetPlacement(kind: .pace, size: .oneByOne, row: -1, column: 0)

        #expect(DashboardLayoutValidator.violations(in: page(tooLow)) == [.outOfBounds(tooLow)])
        #expect(DashboardLayoutValidator.violations(in: page(tooWide)) == [.outOfBounds(tooWide)])
        #expect(DashboardLayoutValidator.violations(in: page(negative)) == [.outOfBounds(negative)])
    }

    @Test("A size the widget has no layout for is rejected")
    func unsupportedSize() {
        let bigPace = WidgetPlacement(kind: .pace, size: .twoByTwo, row: 0, column: 0)
        #expect(DashboardLayoutValidator.violations(in: page(bigPace)) == [.unsupportedSize(bigPace)])
    }

    @Test("Two widgets sharing a cell overlap")
    func overlap() {
        let speed = WidgetPlacement(kind: .speed, size: .twoByTwo, row: 0, column: 0)
        let pace = WidgetPlacement(kind: .pace, size: .oneByOne, row: 1, column: 1)
        #expect(DashboardLayoutValidator.violations(in: page(speed, pace)) == [.overlap(.init(row: 1, column: 1))])
    }

    @Test("A widget kind appears at most once per page")
    func duplicateKind() {
        let left = WidgetPlacement(kind: .pace, size: .oneByOne, row: 0, column: 0)
        let right = WidgetPlacement(kind: .pace, size: .oneByOne, row: 0, column: 1)
        #expect(DashboardLayoutValidator.violations(in: page(left, right)) == [.duplicateKind(.pace)])
    }

    @Test("The same kind on two pages is fine, and empty cells are allowed")
    func sameKindAcrossPages() {
        let layout = DashboardLayout(pages: [
            page(WidgetPlacement(kind: .pace, size: .oneByOne, row: 0, column: 0)),
            page(WidgetPlacement(kind: .pace, size: .oneByOne, row: 6, column: 1)),
        ])
        #expect(DashboardLayoutValidator.isValid(layout))
    }

    @Test("A layout needs at least one page")
    func emptyLayoutIsInvalid() {
        #expect(!DashboardLayoutValidator.isValid(DashboardLayout(pages: [])))
    }
}
