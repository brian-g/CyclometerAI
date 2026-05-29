import Testing
@testable import Cyclometer

@Suite("HeartRateZone — Karvonen formula")
struct HeartRateZoneTests {
    // Fixture: maxHR=190, restingHR=55, HRR=135

    @Test("48% HRR → Zone 1 (Recovery)")
    func zone1() {
        // 48% of 135 = 64.8 + 55 = 119.8 bpm
        let z = HeartRateZone.zone(bpm: 119, maxHR: 190, restingHR: 55)
        #expect(z == .zone1)
    }

    @Test("65% HRR → Zone 2 (Endurance)")
    func zone2() {
        // 65% of 135 = 87.75 + 55 = 142.75 bpm
        let z = HeartRateZone.zone(bpm: 142, maxHR: 190, restingHR: 55)
        #expect(z == .zone2)
    }

    @Test("75% HRR → Zone 3 (Tempo)")
    func zone3() {
        // 75% of 135 = 101.25 + 55 = 156.25 bpm
        let z = HeartRateZone.zone(bpm: 156, maxHR: 190, restingHR: 55)
        #expect(z == .zone3)
    }

    @Test("85% HRR → Zone 4 (Threshold)")
    func zone4() {
        // 85% of 135 = 114.75 + 55 = 169.75 bpm
        let z = HeartRateZone.zone(bpm: 169, maxHR: 190, restingHR: 55)
        #expect(z == .zone4)
    }

    @Test("95% HRR → Zone 5 (VO₂ Max)")
    func zone5() {
        // 95% of 135 = 128.25 + 55 = 183.25 bpm
        let z = HeartRateZone.zone(bpm: 183, maxHR: 190, restingHR: 55)
        #expect(z == .zone5)
    }

    @Test("Zero HRR guard returns Zone 1")
    func zeroHRR() {
        let z = HeartRateZone.zone(bpm: 150, maxHR: 170, restingHR: 170)
        #expect(z == .zone1)
    }
}
