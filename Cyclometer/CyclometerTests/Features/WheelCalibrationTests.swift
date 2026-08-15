import Testing
import Foundation
@testable import Cyclometer

/// PRD §8.9 — "Unit tested: calibration math correct for a range of known discrepancy
/// scenarios". Pure arithmetic, so no store, clock or storage is involved.
@Suite("WheelCalibration math")
struct WheelCalibrationTests {

    /// 700c × 23. Fixtures are built by choosing a measurement that misses it by a
    /// stated fraction.
    private static let stored = 2096

    /// The measurement a window produces when the stored circumference over-reports
    /// distance by `error` (negative = under-reports).
    private func measured(offBy error: Double, from storedMM: Int = stored) -> Double {
        Double(storedMM) / (1 + error)
    }

    /// One window end to end: nil unless it clears the threshold.
    private func correction(offBy error: Double, from storedMM: Int = stored) -> Int? {
        let m = measured(offBy: error, from: storedMM)
        guard WheelCalibration.exceedsThreshold(storedMM: storedMM, measuredMM: m) else { return nil }
        return WheelCalibration.correctedCircumferenceMM(storedMM: storedMM, measuredMM: m)
    }

    // MARK: Measurement

    @Test("Measurement is the stored value divided out — GPS metres per revolution")
    func measurementIsStoredIndependent() {
        // 1500 m over 715.65 revolutions is a 2096 mm wheel, whatever is stored.
        let revs = 1500.0 * 1000 / 2096
        #expect(abs(WheelCalibration.measuredCircumferenceMM(
            gpsMeters: 1500, revolutions: revs
        )! - 2096) < 0.001)
    }

    @Test("Degenerate inputs produce no measurement")
    func degenerateInputs() {
        #expect(WheelCalibration.measuredCircumferenceMM(gpsMeters: 1500, revolutions: 0) == nil)
        #expect(WheelCalibration.measuredCircumferenceMM(gpsMeters: 0, revolutions: 700) == nil)
        #expect(WheelCalibration.measuredCircumferenceMM(gpsMeters: -5, revolutions: 700) == nil)
    }

    // MARK: Trigger threshold

    @Test("A discrepancy inside the 2% band is left alone")
    func withinThresholdDoesNothing() {
        #expect(correction(offBy: 0.01) == nil)
    }

    @Test("Exactly 2.0% does not trigger — the threshold is strictly greater")
    func exactThresholdDoesNotTrigger() {
        let m = measured(offBy: 0.02)
        #expect(abs(WheelCalibration.discrepancy(storedMM: Self.stored, measuredMM: m) - 0.02) < 1e-9)
        #expect(!WheelCalibration.exceedsThreshold(storedMM: Self.stored, measuredMM: m))
        #expect(correction(offBy: 0.02) == nil)
    }

    @Test("1.9% is quiet, 2.1% acts")
    func straddlingTheThreshold() {
        #expect(correction(offBy: 0.019) == nil)
        #expect(correction(offBy: 0.021) != nil)
    }

    // MARK: Direction

    @Test("Over-reading shrinks the circumference, under-reading grows it")
    func directionOfCorrection() {
        let long = measured(offBy: 0.06)     // stored claims more distance than GPS saw
        let short = measured(offBy: -0.06)
        #expect(WheelCalibration.isOverReading(storedMM: Self.stored, measuredMM: long))
        #expect(!WheelCalibration.isOverReading(storedMM: Self.stored, measuredMM: short))
        #expect(correction(offBy: 0.06)! < Self.stored)
        #expect(correction(offBy: -0.06)! > Self.stored)
    }

    @Test("A 6% over-read corrects to the measured value")
    func correctsToMeasured() {
        let m = measured(offBy: 0.06)
        #expect(correction(offBy: 0.06) == Int(m.rounded()))
    }

    // MARK: Cap and rejection

    @Test("A 30% over-read is capped at −10% of the stored value")
    func largeOverReadIsCapped() {
        #expect(correction(offBy: 0.30) == Int((Double(Self.stored) * 0.90).rounded()))
    }

    @Test("A 30% under-read is capped at +10% of the stored value")
    func largeUnderReadIsCapped() {
        #expect(correction(offBy: -0.30) == Int((Double(Self.stored) * 1.10).rounded()))
    }

    @Test("A result outside the sanity range is rejected, not clamped to the boundary")
    func implausibleResultIsRejected() {
        // Stored near the top of the range: the +10% cap lands above 3,000 mm, which
        // is the case the range check exists for. Clamping would quietly commit it.
        let stored = WheelPreset.validRange.upperBound - 50   // 2950
        let capped = Double(stored) * 1.10                    // 3245
        #expect(!WheelPreset.validRange.contains(Int(capped.rounded())))
        #expect(correction(offBy: -0.30, from: stored) == nil)
    }

    @Test("A correction that rounds back to the stored value is not a change")
    func noOpCorrectionIsRejected() {
        #expect(WheelCalibration.correctedCircumferenceMM(
            storedMM: Self.stored, measuredMM: Double(Self.stored) + 0.2
        ) == nil)
    }

    // MARK: Averaging confirming windows

    @Test("Averaging two confirming windows lands between them")
    func averagedCorrection() {
        // The shipped field case: windows measured 2051 and 2069 against a stored
        // 2288. Committing the second alone gave 2069; the mean is 2060.
        let mean = (2051.0 + 2069.0) / 2
        #expect(WheelCalibration.correctedCircumferenceMM(storedMM: 2288, measuredMM: mean) == 2060)
        #expect(WheelCalibration.correctedCircumferenceMM(storedMM: 2288, measuredMM: 2069) == 2069)
    }

    @Test("The ±10% cap still binds after averaging")
    func averagingDoesNotEscapeTheCap() {
        // Both windows agree the wheel is far smaller than stored; the cap holds.
        let mean = (1700.0 + 1720.0) / 2
        #expect(WheelCalibration.correctedCircumferenceMM(storedMM: 2288, measuredMM: mean)
                == Int((2288.0 * 0.90).rounded()))
    }

    // MARK: Presentation

    @Test("Banner text matches the PRD wording")
    func bannerText() {
        #expect(WheelCalibration.bannerText(mm: 2145) == "Wheel size auto-adjusted to 2145 mm")
    }
}
