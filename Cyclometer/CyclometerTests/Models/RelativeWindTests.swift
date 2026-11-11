import Testing
@testable import Cyclometer

/// #150 — W10's arrow: the wind relative to the rider's direction of travel.
@Suite("RelativeWind")
struct RelativeWindTests {

    struct Case: CustomTestStringConvertible, Sendable {
        let windFrom, course, rotation: Double
        let wind: RelativeWind

        var testDescription: String { "wind from \(windFrom)°, heading \(course)°" }
    }

    static let cases: [Case] = [
        // The issue's example: heading south with a northerly, the arrow points forward.
        Case(windFrom: 0, course: 180, rotation: 0, wind: .tailwind),
        Case(windFrom: 0, course: 0, rotation: 180, wind: .headwind),
        // Heading north, a westerly blows left to right: the arrow points right.
        Case(windFrom: 270, course: 0, rotation: 90, wind: .crosswindFromLeft),
        Case(windFrom: 90, course: 0, rotation: 270, wind: .crosswindFromRight),
        // Either side of north, where the sum wraps past 360 or below 0.
        Case(windFrom: 350, course: 10, rotation: 160, wind: .headwind),
        Case(windFrom: 10, course: 350, rotation: 200, wind: .headwind),
        // Each quarter runs 45° either side of its direction; an edge belongs to the quarter after it.
        Case(windFrom: 224, course: 0, rotation: 44, wind: .tailwind),
        Case(windFrom: 225, course: 0, rotation: 45, wind: .crosswindFromLeft),
        Case(windFrom: 315, course: 0, rotation: 135, wind: .headwind),
        Case(windFrom: 45, course: 0, rotation: 225, wind: .crosswindFromRight),
        Case(windFrom: 135, course: 0, rotation: 315, wind: .tailwind),
    ]

    @Test("The arrow turns to where the wind blows, with up as the direction of travel", arguments: cases)
    func rotationAndQuarter(_ testCase: Case) {
        #expect(RelativeWind.arrowRotation(windFrom: testCase.windFrom, course: testCase.course) == testCase.rotation)
        #expect(RelativeWind(windFrom: testCase.windFrom, course: testCase.course) == testCase.wind)
    }

    @Test("A bearing that isn't a number points the arrow forward rather than trapping")
    func nonFinite() {
        #expect(RelativeWind.arrowRotation(windFrom: .nan, course: 90) == 0)
        #expect(RelativeWind.arrowRotation(windFrom: 90, course: .infinity) == 0)
    }
}
