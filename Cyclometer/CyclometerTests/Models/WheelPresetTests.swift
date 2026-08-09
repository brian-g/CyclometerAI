import Testing
@testable import Cyclometer

@Suite("WheelPreset")
struct WheelPresetTests {

    /// The canonical table from PRD §8.9, in spec order (which is picker order).
    private static let specTable: [(WheelPreset, String, Int)] = [
        (.c700x23,  "700 x 23c",  2096),
        (.c700x25,  "700 x 25c",  2105),
        (.c700x28,  "700 x 28c",  2136),
        (.c700x32,  "700 x 32c",  2155),
        (.c700x35,  "700 x 35c",  2168),
        (.b650x47,  "650b x 47",  2144),
        (.mtb29x21, "29 x 2.1",   2288),
        (.mtb26x20, "26 x 2.0",   2051)
    ]

    @Test("All eight presets match the PRD §8.9 table, in spec order")
    func presetsMatchSpec() {
        #expect(WheelPreset.allCases.count == Self.specTable.count)
        for (index, expected) in Self.specTable.enumerated() {
            let preset = WheelPreset.allCases[index]
            #expect(preset == expected.0)
            #expect(preset.label == expected.1)
            #expect(preset.circumferenceMM == expected.2)
        }
    }

    /// `WheelPreset(rawValue:)` is used as the "is this stored value a preset?"
    /// test, which only holds if no two presets share a circumference.
    @Test("Circumferences are unique, so rawValue lookup is unambiguous")
    func circumferencesAreUnique() {
        let values = WheelPreset.allCases.map(\.circumferenceMM)
        #expect(Set(values).count == values.count)
    }

    @Test("Default preset matches the CSC client's built-in default")
    func defaultMatchesClientDefault() {
        #expect(WheelPreset.default == .c700x23)
        #expect(WheelPreset.default.circumferenceMM == 2096)
    }

    @Test("Manual-entry bounds are 1,500–3,000 mm and admit every preset")
    func validRangeBounds() {
        #expect(WheelPreset.validRange == 1500...3000)
        for preset in WheelPreset.allCases {
            #expect(WheelPreset.validRange.contains(preset.circumferenceMM))
        }
    }
}
