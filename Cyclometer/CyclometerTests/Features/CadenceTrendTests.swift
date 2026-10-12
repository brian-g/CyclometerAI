import Testing
@testable import Cyclometer

/// #402 — W5's ▲/▼: current cadence against the ride average, as W1's speed is.
@Suite("Cadence Trend")
struct CadenceTrendTests {

    @Test func aboveAndBelowAverage() {
        #expect(CadenceWidget.trend(cadence: 94, average: 88) == .up)
        #expect(CadenceWidget.trend(cadence: 82, average: 88) == .down)
    }

    /// Within `trendThresholdRPM` is even, as W1's 0.5 km/h is.
    @Test func withinThresholdIsSteady() {
        #expect(CadenceWidget.trend(cadence: 93, average: 88) == .steady)
        #expect(CadenceWidget.trend(cadence: 83, average: 88) == .steady)
    }

    /// Coasting, no reading, or no pedalling recorded yet: nothing to compare.
    @Test func noComparisonIsSteady() {
        #expect(CadenceWidget.trend(cadence: 0, average: 88) == .steady)
        #expect(CadenceWidget.trend(cadence: nil, average: 88) == .steady)
        #expect(CadenceWidget.trend(cadence: 92, average: 0) == .steady)
    }
}
