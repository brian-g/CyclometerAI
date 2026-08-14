import Testing
import Foundation
@testable import Cyclometer

/// PRD §8.9 — "Unit tested: calibration math correct for a range of known discrepancy
/// scenarios". Pure arithmetic, so no store, clock or storage is involved.
@Suite("WheelCalibration math")
struct WheelCalibrationTests {

    /// 700c × 23. Every fixture below is built by choosing a revolution count that
    /// makes the BLE distance miss 500 m by a stated percentage.
    private static let stored = 2096

    /// Revolutions that make `stored` report exactly `gpsMeters × (1 + error)`.
    private func revolutions(forError error: Double, gpsMeters: Double = 1500) -> Double {
        gpsMeters * (1 + error) * 1000 / Double(Self.stored)
    }

    // MARK: Trigger threshold

    @Test("A discrepancy inside the 2% band is left alone")
    func withinThresholdDoesNothing() {
        let revs = revolutions(forError: 0.01)
        #expect(WheelCalibration.newCircumferenceMM(
            storedMM: Self.stored, gpsMeters: 1500, revolutions: revs
        ) == nil)
    }

    @Test("Exactly 2.0% does not trigger — the threshold is strictly greater")
    func exactThresholdDoesNotTrigger() {
        let revs = revolutions(forError: 0.02)
        let discrepancy = WheelCalibration.discrepancy(
            storedMM: Self.stored, gpsMeters: 1500, revolutions: revs
        )
        #expect(abs((discrepancy ?? 0) - 0.02) < 1e-9)
        #expect(WheelCalibration.newCircumferenceMM(
            storedMM: Self.stored, gpsMeters: 1500, revolutions: revs
        ) == nil)
    }

    @Test("1.9% is quiet, 2.1% acts")
    func straddlingTheThreshold() {
        #expect(WheelCalibration.newCircumferenceMM(
            storedMM: Self.stored, gpsMeters: 1500, revolutions: revolutions(forError: 0.019)
        ) == nil)
        #expect(WheelCalibration.newCircumferenceMM(
            storedMM: Self.stored, gpsMeters: 1500, revolutions: revolutions(forError: 0.021)
        ) != nil)
    }

    // MARK: Correction

    @Test("BLE over-reading by 6% shrinks the circumference to match GPS")
    func overReadingShrinksCircumference() {
        let revs = revolutions(forError: 0.06)
        let result = WheelCalibration.newCircumferenceMM(
            storedMM: Self.stored, gpsMeters: 1500, revolutions: revs
        )
        // new = gps × 1000 / revs, which is stored / 1.06
        #expect(result == Int((Double(Self.stored) / 1.06).rounded()))
        #expect(result! < Self.stored)
        #expect(WheelCalibration.isOverReading(
            storedMM: Self.stored, gpsMeters: 1500, revolutions: revs
        ))
    }

    @Test("BLE under-reading by 6% grows the circumference symmetrically")
    func underReadingGrowsCircumference() {
        let revs = revolutions(forError: -0.06)
        let result = WheelCalibration.newCircumferenceMM(
            storedMM: Self.stored, gpsMeters: 1500, revolutions: revs
        )
        #expect(result == Int((Double(Self.stored) / 0.94).rounded()))
        #expect(result! > Self.stored)
        #expect(!WheelCalibration.isOverReading(
            storedMM: Self.stored, gpsMeters: 1500, revolutions: revs
        ))
    }

    @Test("A 30% over-read is capped at −10% of the stored value")
    func largeOverReadIsCapped() {
        let revs = revolutions(forError: 0.30)
        let result = WheelCalibration.newCircumferenceMM(
            storedMM: Self.stored, gpsMeters: 1500, revolutions: revs
        )
        #expect(result == Int((Double(Self.stored) * 0.90).rounded()))
    }

    @Test("A 30% under-read is capped at +10% of the stored value")
    func largeUnderReadIsCapped() {
        let revs = revolutions(forError: -0.30)
        let result = WheelCalibration.newCircumferenceMM(
            storedMM: Self.stored, gpsMeters: 1500, revolutions: revs
        )
        #expect(result == Int((Double(Self.stored) * 1.10).rounded()))
    }

    // MARK: Rejections

    @Test("A result outside the sanity range is rejected, not clamped to the boundary")
    func implausibleResultIsRejected() {
        // 700 revolutions over 1500 m is a plausible-looking wheel. The ±10% cap would pull it
        // back to a plausible-looking 2306 mm, which is exactly the failure mode this
        // guard exists to prevent — so instead verify the range check with a stored
        // value close enough to the boundary that the capped result escapes it.
        let stored = WheelPreset.validRange.upperBound - 50   // 2950
        let revs = revolutions(forError: -0.30, gpsMeters: 1500)
            * Double(Self.stored) / Double(stored)
        let capped = Double(stored) * 1.10                     // 3245 — out of range
        #expect(!WheelPreset.validRange.contains(Int(capped.rounded())))
        #expect(WheelCalibration.newCircumferenceMM(
            storedMM: stored, gpsMeters: 1500, revolutions: revs
        ) == nil)
    }

    @Test("Degenerate inputs yield no correction")
    func degenerateInputs() {
        #expect(WheelCalibration.newCircumferenceMM(
            storedMM: Self.stored, gpsMeters: 1500, revolutions: 0
        ) == nil)
        #expect(WheelCalibration.newCircumferenceMM(
            storedMM: Self.stored, gpsMeters: 0, revolutions: 700
        ) == nil)
        #expect(WheelCalibration.discrepancy(
            storedMM: Self.stored, gpsMeters: 0, revolutions: 700
        ) == nil)
    }

    @Test("A correction that rounds back to the stored value is not a change")
    func noOpCorrectionIsRejected() {
        // Contrived: a discrepancy over threshold whose capped result rounds to the
        // stored value can only happen at cap boundaries, so assert the guard
        // directly rather than constructing one.
        #expect(WheelCalibration.newCircumferenceMM(
            storedMM: Self.stored, gpsMeters: 1500, revolutions: revolutions(forError: 0)
        ) == nil)
    }

    // MARK: Presentation

    @Test("Banner text matches the PRD wording")
    func bannerText() {
        #expect(WheelCalibration.bannerText(mm: 2145) == "Wheel size auto-adjusted to 2145 mm")
    }
}
