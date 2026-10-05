import Testing
@testable import Cyclometer

/// S08's picker (#142): what it lists, and in what order.
struct AddWidgetSheetTests {
    private func names(_ entries: [AddWidgetEntry]) -> [String] {
        entries.map { "\($0.widget.id) \($0.size)" }
    }

    @Test("A category lists every 2×2, then every 2×1, then every 1×1, each in catalog order")
    func entriesLargestFirst() {
        #expect(names(AddWidgetEntry.entries(in: .ride)) == [
            "speed twoByTwo",
            "speed twoByOne", "cadence twoByOne",
            "speed oneByOne", "averageSpeed oneByOne", "duration oneByOne", "distance oneByOne",
            "cadence oneByOne", "pace oneByOne",
        ])
        #expect(names(AddWidgetEntry.entries(in: .heartRate)) == ["heartRate oneByOne", "hrZones oneByOne"])
        #expect(names(AddWidgetEntry.entries(in: .route)) == ["map twoByTwo", "directions twoByOne", "directions oneByOne"])
    }

    /// Issue AC: every widget appears, at every size it supports — once.
    @Test("Every widget appears at every supported size exactly once")
    func everyWidgetAndSizeOnce() {
        let listed = WidgetCategory.allCases.flatMap { names(AddWidgetEntry.entries(in: $0)) }
        let expected = DashboardWidgetCatalog.all.flatMap { widget in widget.supportedSizes.map { "\(widget.id) \($0)" } }
        #expect(listed.count == Set(listed).count)
        #expect(Set(listed) == Set(expected))
    }

    @Test("Full-width entries sit alone; 1×1s pair up, a lone one last")
    func rowsPairOneByOnes() {
        let rows = AddWidgetEntry.rows(AddWidgetEntry.entries(in: .ride)).map(names)
        #expect(rows == [
            ["speed twoByTwo"],
            ["speed twoByOne"],
            ["cadence twoByOne"],
            ["speed oneByOne", "averageSpeed oneByOne"],
            ["duration oneByOne", "distance oneByOne"],
            ["cadence oneByOne", "pace oneByOne"],
        ])
        #expect(AddWidgetEntry.rows(AddWidgetEntry.entries(in: .route)).map(names) == [
            ["map twoByTwo"],
            ["directions twoByOne"],
            ["directions oneByOne"],
        ])
    }
}
