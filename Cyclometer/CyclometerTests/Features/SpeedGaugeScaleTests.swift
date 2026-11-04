import Foundation
import Testing
@testable import Cyclometer

@Suite("SpeedGaugeScale — W1 option B's gauge scale (#534)")
struct SpeedGaugeScaleTests {
    private func mps(kmh: Double) -> Double {
        Measurement(value: kmh, unit: UnitSpeed.kilometersPerHour).converted(to: .metersPerSecond).value
    }

    private func mps(mph: Double) -> Double {
        Measurement(value: mph, unit: UnitSpeed.milesPerHour).converted(to: .metersPerSecond).value
    }

    @Test("The scale is 0–60 km/h or 0–40 mph until the ride's max passes it")
    func baseScale() {
        #expect(SpeedGaugeScale.top(maxSpeedMPS: 0, unit: .metric) == 60)
        #expect(SpeedGaugeScale.top(maxSpeedMPS: mps(kmh: 60), unit: .metric) == 60)
        #expect(SpeedGaugeScale.top(maxSpeedMPS: 0, unit: .imperial) == 40)
        #expect(SpeedGaugeScale.top(maxSpeedMPS: mps(mph: 39.9), unit: .imperial) == 40)
    }

    @Test("A max past the top grows the scale to the next 10")
    func growsPastTop() {
        #expect(SpeedGaugeScale.top(maxSpeedMPS: mps(kmh: 60.1), unit: .metric) == 70)
        #expect(SpeedGaugeScale.top(maxSpeedMPS: mps(kmh: 72), unit: .metric) == 80)
        #expect(SpeedGaugeScale.top(maxSpeedMPS: mps(mph: 41), unit: .imperial) == 50)
    }

    @Test("Ticks every 5 between the ends")
    func ticks() {
        #expect(SpeedGaugeScale.ticks(top: 40) == [5, 10, 15, 20, 25, 30, 35])
        #expect(SpeedGaugeScale.ticks(top: 60).count == 11)
    }

    @Test("A speed's place on the arc is clamped to its ends")
    func fraction() {
        #expect(abs(SpeedGaugeScale.fraction(ofMPS: mps(kmh: 30), top: 60, unit: .metric) - 0.5) < 1e-9)
        #expect(SpeedGaugeScale.fraction(ofMPS: mps(kmh: 75), top: 60, unit: .metric) == 1)
        #expect(SpeedGaugeScale.fraction(ofMPS: 0, top: 60, unit: .metric) == 0)
    }
}
