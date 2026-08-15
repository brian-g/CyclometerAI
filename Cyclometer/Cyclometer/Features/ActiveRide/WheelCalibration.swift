import Foundation

/// GPS auto-calibration of wheel circumference — the arithmetic and its thresholds,
/// with no state, clock or storage, so it can be exercised directly (PRD §8.9).
///
/// The premise: GPS is too noisy for per-second speed, which is why BLE has priority,
/// but over a 500 m window it is accurate enough to catch a wheel circumference that
/// has drifted from the truth through tyre wear, pressure or a tyre swap nobody
/// recorded in Settings.
enum WheelCalibration {
    /// GPS metres accumulated before a window is evaluated.
    ///
    /// PRD §8.9 specifies 500 m. Raised because the largest error term — where the
    /// window boundaries fall relative to the ~1 Hz BLE notifications — is a fixed
    /// *duration*, so it shrinks only by lengthening the window. It is zero-mean
    /// (see `WheelCalibrationFeature.wheelRevolutionsReceived`) but its spread is
    /// ~0.8% of a 500 m window against ~0.27% of a 1500 m one, and the threshold
    /// below needs room above it.
    static let windowThresholdMeters = 1500.0

    /// A window must miss by more than this to be worth acting on.
    ///
    /// PRD §8.9 specifies 5%. Lowered because 5% excludes every cause the spec itself
    /// names: tread wear (0.3–0.8%), inflation (0.3–1%) and rider weight (0.3–0.5%)
    /// are all an order of magnitude below it, and Sheldon Brown puts the population
    /// this feature targets — riders on a default or charted wheel size — at "2% or
    /// more". The whole 700c preset range spans just 3.4%, so at 5% no road rider who
    /// picked the wrong preset could ever be corrected.
    ///
    /// 2% sits ~4× above this estimator's combined error floor at a 1500 m window,
    /// which is ample: GPS speed error is zero-mean and averages down as √N, so the
    /// floor is well under 1%.
    static let discrepancyThreshold = 0.02
    /// Ceiling on a single correction, so one bad window cannot move the rider's
    /// wheel size far. A genuinely large error converges across several windows.
    static let maxAdjustmentFraction = 0.10
    /// Fixes worse than this are unreliable enough that the window is paused.
    static let maxHorizontalAccuracy = 10.0
    /// Below this the rider is stopped or crawling, where both estimators are noise
    /// and GPS scatter accumulates distance the wheel never travelled.
    static let minMovingSpeedMPS = 2.0
    /// A longer gap between fixes means position was lost; the interval can't be
    /// integrated and the window is no longer aligned with the revolution count.
    static let maxGPSGap: TimeInterval = 3.0
    /// Consecutive same-direction windows required before a correction is committed.
    /// PRD §8.9's acceptance criterion asks for a discrepancy *sustained* over the
    /// window, and this is what makes a single anomalous window harmless — which
    /// matters because a commit silently rewrites a setting the rider chose.
    static let confirmationWindows = 2
    /// Backstop against any pathology not anticipated here. A ride needing more than
    /// three corrections has something wrong that calibration should not paper over.
    static let maxCommitsPerRide = 3

    /// Metres the wheel covered for `revolutions` at `circumferenceMM`.
    static func bleDistance(revolutions: Double, circumferenceMM: Int) -> Double {
        revolutions * Double(circumferenceMM) / 1000.0
    }

    /// What this window says the wheel actually rolls, in millimetres — nil if the
    /// inputs can't support a measurement.
    ///
    /// PRD §8.9 states the correction as `stored × (GPS / BLE)`. Substituting
    /// `BLE = revolutions × stored / 1000` cancels `stored` entirely, leaving
    /// `GPS × 1000 / revolutions`. The stored value survives only in the trigger test
    /// and the ±10% cap, which is what makes the measurement immune to the
    /// circumference being changed in Settings partway through a window — and what
    /// lets measurements from several windows be averaged before a correction is
    /// derived from them.
    static func measuredCircumferenceMM(gpsMeters: Double, revolutions: Double) -> Double? {
        guard gpsMeters > 0, revolutions > 0 else { return nil }
        return gpsMeters * 1000.0 / revolutions
    }

    /// `|BLE − GPS| / GPS` over the window, which reduces to
    /// `|stored − measured| / measured`. Unsigned; use `isOverReading` for direction.
    static func discrepancy(storedMM: Int, measuredMM: Double) -> Double {
        abs(Double(storedMM) - measuredMM) / measuredMM
    }

    /// Whether a window missed by enough to be worth acting on.
    static func exceedsThreshold(storedMM: Int, measuredMM: Double) -> Bool {
        discrepancy(storedMM: storedMM, measuredMM: measuredMM) > discrepancyThreshold
    }

    /// True when the stored circumference makes the wheel claim more distance than
    /// GPS saw — i.e. the correction will shrink it. Used to require that consecutive
    /// windows agree on the direction before committing.
    static func isOverReading(storedMM: Int, measuredMM: Double) -> Bool {
        Double(storedMM) > measuredMM
    }

    /// The value to commit for a confirmed measurement, or nil when none is warranted.
    ///
    /// Takes the measurement rather than raw window data so the caller can average the
    /// windows that confirmed each other first — two windows agreeing is what licenses
    /// the correction, so discarding the first one's measurement throws away half the
    /// evidence and leaves `√2` of avoidable error on the table.
    ///
    /// Returns nil when the result lands outside `WheelPreset.validRange`. That is a
    /// *rejection*, not a clamp: a value that implausible means the measurement was
    /// wrong, and pinning it to a boundary would commit garbage while looking
    /// deliberate.
    static func correctedCircumferenceMM(storedMM: Int, measuredMM: Double) -> Int? {
        let lower = Double(storedMM) * (1 - maxAdjustmentFraction)
        let upper = Double(storedMM) * (1 + maxAdjustmentFraction)
        let capped = min(max(measuredMM, lower), upper)

        let rounded = Int(capped.rounded())
        guard WheelPreset.validRange.contains(rounded) else { return nil }
        guard rounded != storedMM else { return nil }
        return rounded
    }

    static func bannerText(mm: Int) -> String {
        "Wheel size auto-adjusted to \(mm) mm"
    }
}
