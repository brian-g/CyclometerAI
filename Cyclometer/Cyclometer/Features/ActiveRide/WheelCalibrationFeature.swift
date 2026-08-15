import ComposableArchitecture
import Foundation
import os

private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "ble")

/// Compares BLE wheel distance against GPS distance over rolling 1,500 m windows and
/// corrects `AppPreferences.wheelCircumferenceMM` when they disagree materially
/// (PRD §8.9, thresholds and their rationale in §8.9.2, TCA.md §4.11).
///
/// This reducer writes a setting the rider chose, without asking, and the change
/// outlives the ride — a false correction silently distorts speed and distance on
/// every subsequent ride until someone notices. Everything below is shaped by that:
/// the window is abandoned at the first sign its two halves disagree about what
/// interval they cover, and a correction needs two consecutive windows to agree.
///
/// **The alignment invariant.** The GPS and BLE accumulators must always describe the
/// same stretch of riding. Every gate therefore suppresses *both* — dropping a
/// poor-accuracy fix while revolutions keep accruing would manufacture exactly the
/// discrepancy this feature exists to detect. Gates are sticky flags read when a
/// sample lands, never per-sample filters.
///
/// Accepted residual: BLE notifications and GPS fixes arrive on independent ~1 Hz
/// phases, so where a window's boundaries fall relative to each stream shifts what it
/// counts. The error is zero-mean (see `wheelRevolutionsReceived`) with a spread of
/// ~0.27% of a 1,500 m window.
///
/// **Field-verified 2026-08-15.** Six windows across two rides on the same bike
/// measured 2057, 2069, 2069, 2055, 2051 and 2069 mm — mean 2061.8, sd 8.4 mm
/// (0.41%), against the ~0.49% predicted floor. A ride started at 2288 mm (29 × 2.1)
/// corrected to 2069 mm after two confirming windows, persisted, and showed the
/// banner; Settings then read Custom 2069 mm. That ride is also why `commit` averages
/// the confirming windows: it committed the second window's 2069 where the mean of
/// both was 2060, and the pooled evidence puts the truth near 2062.
@Reducer
struct WheelCalibrationFeature {
    /// How long the calibration banner stays up. Matches `SpeedFeature`.
    static let bannerDismissDelay: Duration = .seconds(4)

    @Dependency(\.bleCSCClient) var bleCSCClient
    @Dependency(\.continuousClock) var clock
    @Dependency(\.date.now) var now

    @ObservableState
    struct State: Equatable {
        /// Write access — this feature is the auto-calibration half of the two paths
        /// that own this value; `SettingsFeature` is the manual half.
        @Shared(.appPreferences) var preferences

        /// Driven by `ActiveRideFeature` via `.suspensionChanged`: an L2/L3 radar
        /// alert is up, or the ride isn't actively recording.
        ///
        /// Defaults to `false` so it agrees with the parent's derived value for a
        /// state constructed mid-ride; nothing accumulates on this alone, since
        /// `isSensorActive` and `isGPSUsable` both start closed.
        var isSuspended = false
        /// The paired speed sensor is connected and delivering. Anything else voids
        /// the window outright — a reconnect gap loses revolutions that GPS kept
        /// counting through, and the calculator will never replay them.
        var isSensorActive = false
        /// The last fix was usable. Sticky, so it gates revolutions too.
        var isGPSUsable = false

        var gpsMeters = 0.0
        var revolutions = 0.0
        var lastFixTimestamp: Date?

        /// Direction the last qualifying window pointed, and the measurement from
        /// every consecutive window that has agreed with it. Reset by a sign flip or a
        /// clean window.
        ///
        /// The measurements are kept, not just counted: two windows agreeing is what
        /// licenses the correction, so both should inform its value.
        var pendingOverReading: Bool?
        var pendingMeasurements: [Double] = []
        var confirmedWindows: Int { pendingMeasurements.count }

        var commitCount = 0
        var lastCalibrationAt: Date?
        /// Transient banner text; nil means hidden.
        var banner: String?

        /// Both accumulators advance only while every gate is open.
        var isAccumulating: Bool { isSensorActive && isGPSUsable && !isSuspended }
    }

    enum Action: Equatable {
        case startListening
        case wheelRevolutionsReceived(Double)
        case bleConnectionChanged(BLECSCClient.ConnectionState)
        case locationUpdated(LocationUpdate)
        /// Sent by the parent only when the value actually flips — radar targets
        /// arrive continuously and an action per update would be pure churn.
        case suspensionChanged(Bool)
        case bannerDismissed
    }

    private enum CancelID { case bannerTimer }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .startListening:
                // No explicit teardown: `AppFeature` holds the ride behind `ifLet`,
                // which cancels every child effect when the ride state goes nil at
                // ride end. An explicit stop action would race that — it arrives as
                // an effect, after the state it belongs to is already gone.
                return .merge(
                    .run { [bleCSCClient] send in
                        for await revolutions in bleCSCClient.wheelRevolutions() {
                            await send(.wheelRevolutionsReceived(revolutions))
                        }
                    },
                    .run { [bleCSCClient] send in
                        for await connectionState in bleCSCClient.connectionState(.speed) {
                            await send(.bleConnectionChanged(connectionState))
                        }
                    }
                )

            case .bleConnectionChanged(let connectionState):
                let isActive = connectionState == .active
                // Leaving `.active` opens a hole in the revolution count that GPS does
                // not have, so the window cannot be salvaged — unlike a suspension,
                // which pauses both sides together.
                if state.isSensorActive, !isActive {
                    logger.notice("calibration window voided — speed sensor left .active")
                    resetWindow(&state)
                }
                if state.isSensorActive != isActive {
                    logger.notice("calibration sensor gate \(isActive ? "open" : "shut", privacy: .public)")
                }
                state.isSensorActive = isActive
                return .none

            case .wheelRevolutionsReceived(let revolutions):
                // The delta straddling the window start is counted whole, and the
                // riding after the last delta before the window closes is not counted
                // at all. Those two truncations are drawn from the same distribution
                // and enter with opposite signs, so the error is zero-mean — roughly
                // ±0.3% of a 1500 m window, one standard deviation. Discarding the
                // straddling delta would leave only the second truncation and turn a
                // zero-mean error into a systematic one-notification undercount.
                guard state.isAccumulating else { return .none }
                state.revolutions += revolutions
                return .none

            case .locationUpdated(let update):
                guard isFixUsable(update, since: state.lastFixTimestamp) else {
                    // Pause rather than discard: the accumulators still describe a
                    // consistent stretch, and clearing the timestamp means the first
                    // fix after recovery re-seeds the interval instead of integrating
                    // across the gap.
                    if state.isGPSUsable {
                        logger.notice(
                            """
                            calibration gps gate shut — accuracy \
                            \(update.horizontalAccuracy, format: .fixed(precision: 1), privacy: .public) m, \
                            speed \(update.speed, format: .fixed(precision: 1), privacy: .public) m/s
                            """
                        )
                    }
                    state.isGPSUsable = false
                    state.lastFixTimestamp = nil
                    return .none
                }

                let wasUsable = state.isGPSUsable
                if !wasUsable { logger.notice("calibration gps gate open") }
                state.isGPSUsable = true
                defer { state.lastFixTimestamp = update.timestamp }

                // A fix that only re-seeds the interval contributes no distance, and
                // neither does one that arrives while some other gate is shut.
                guard wasUsable, let previous = state.lastFixTimestamp, state.isAccumulating
                else { return .none }

                // Doppler speed integrated over the interval, not the distance between
                // successive coordinates: position differencing measures |true + noise|,
                // which is biased *upward* by roughly the size of the 5% trigger
                // threshold itself at realistic fix noise. Speed error is zero-mean and
                // averages out across the window.
                state.gpsMeters += update.speed * update.timestamp.timeIntervalSince(previous)

                guard state.gpsMeters >= WheelCalibration.windowThresholdMeters else { return .none }
                return evaluateWindow(&state)

            case .suspensionChanged(let isSuspended):
                // Logged for the same reason the other two gates are: a ride whose
                // windows never complete has to say which gate held them up, and
                // radar-driven suspension is otherwise invisible in a collected log.
                if state.isSuspended != isSuspended {
                    logger.notice(
                        "calibration suspension gate \(isSuspended ? "shut — radar alert or ride not recording" : "open", privacy: .public)"
                    )
                }
                state.isSuspended = isSuspended
                return .none

            case .bannerDismissed:
                state.banner = nil
                return .none
            }
        }
    }

    // MARK: - Window handling

    private func isFixUsable(_ update: LocationUpdate, since previous: Date?) -> Bool {
        guard update.horizontalAccuracy > 0,
              update.horizontalAccuracy <= WheelCalibration.maxHorizontalAccuracy,
              update.speed >= WheelCalibration.minMovingSpeedMPS
        else { return false }
        guard let previous else { return true }
        let gap = update.timestamp.timeIntervalSince(previous)
        return gap > 0 && gap <= WheelCalibration.maxGPSGap
    }

    /// Single funnel for clearing the accumulators, so no path can zero one and leave
    /// the other standing. Leaves the confirmation streak alone — a window that ends
    /// normally hands its verdict to the next one.
    private func resetMeasurements(_ state: inout State) {
        state.gpsMeters = 0
        state.revolutions = 0
        state.lastFixTimestamp = nil
    }

    /// Abandon the window *and* the streak. Used when the data is untrustworthy
    /// rather than merely finished.
    private func resetWindow(_ state: inout State) {
        resetMeasurements(&state)
        state.pendingOverReading = nil
        state.pendingMeasurements = []
    }

    private func evaluateWindow(_ state: inout State) -> Effect<Action> {
        let storedMM = state.preferences.wheelCircumferenceMM
        let gpsMeters = state.gpsMeters
        let revolutions = state.revolutions

        guard let measuredMM = WheelCalibration.measuredCircumferenceMM(
            gpsMeters: gpsMeters, revolutions: revolutions
        ) else {
            resetWindow(&state)
            return .none
        }

        // One line per completed window, at notice so it survives `log collect` after
        // an untethered ride. Without it a silent ride is indistinguishable from a
        // broken one — a window that closes inside the band and a window that never
        // accumulated at all both look like "nothing happened".
        let discrepancy = WheelCalibration.discrepancy(storedMM: storedMM, measuredMM: measuredMM)
        logger.notice(
            """
            calibration window: gps \(gpsMeters, format: .fixed(precision: 1), privacy: .public) m, \
            \(revolutions, format: .fixed(precision: 1), privacy: .public) rev \
            → measured \(measuredMM, format: .fixed(precision: 0), privacy: .public) mm \
            vs stored \(storedMM, privacy: .public) mm \
            (\(discrepancy * 100, format: .fixed(precision: 2), privacy: .public)% \
            of the \(WheelCalibration.discrepancyThreshold * 100, format: .fixed(precision: 0), privacy: .public)% threshold)
            """
        )

        guard WheelCalibration.exceedsThreshold(storedMM: storedMM, measuredMM: measuredMM) else {
            resetWindow(&state)
            return .none
        }

        // A window that disagrees with its predecessor about which way the wheel is
        // wrong is evidence of noise, not drift — start the streak over.
        let isOverReading = WheelCalibration.isOverReading(storedMM: storedMM, measuredMM: measuredMM)
        if state.pendingOverReading == isOverReading {
            state.pendingMeasurements.append(measuredMM)
        } else {
            state.pendingMeasurements = [measuredMM]
        }
        state.pendingOverReading = isOverReading

        guard state.confirmedWindows >= WheelCalibration.confirmationWindows else {
            // The streak and its measurements carry forward; the accumulators do not.
            // The next window must stand on its own data.
            let streak = state.confirmedWindows
            logger.notice(
                """
                calibration over threshold (\(isOverReading ? "wheel reads long" : "wheel reads short", privacy: .public)) — \
                window \(streak, privacy: .public) of \
                \(WheelCalibration.confirmationWindows, privacy: .public) before correcting
                """
            )
            resetMeasurements(&state)
            return .none
        }

        // Every window that confirmed the correction informs its value. Committing the
        // last window's measurement alone would discard half the evidence that
        // licensed the change.
        let measurements = state.pendingMeasurements
        let averagedMM = measurements.reduce(0, +) / Double(measurements.count)

        guard let newMM = WheelCalibration.correctedCircumferenceMM(
            storedMM: storedMM, measuredMM: averagedMM
        ) else {
            resetWindow(&state)
            return .none
        }

        guard state.commitCount < WheelCalibration.maxCommitsPerRide else {
            logger.notice("calibration refused — per-ride cap of \(WheelCalibration.maxCommitsPerRide, privacy: .public) reached")
            resetWindow(&state)
            return .none
        }

        return commit(newMM, storedMM: storedMM, averagedMM: averagedMM,
                      measurements: measurements, to: &state)
    }

    /// Persist and push together, mirroring `SettingsFeature.apply(_:to:)` — the
    /// stored value and the value driving the speed derivation must never drift apart.
    private func commit(
        _ mm: Int, storedMM: Int, averagedMM: Double, measurements: [Double], to state: inout State
    ) -> Effect<Action> {
        state.$preferences.withLock { $0.wheelCircumferenceMM = mm }
        state.lastCalibrationAt = now
        state.commitCount += 1
        state.banner = WheelCalibration.bannerText(mm: mm)
        resetWindow(&state)

        let windows = measurements
            .map { String(format: "%.0f", $0) }
            .joined(separator: ", ")
        logger.notice(
            """
            wheel auto-calibrated \(storedMM, privacy: .public) → \(mm, privacy: .public) mm \
            (mean \(averagedMM, format: .fixed(precision: 1), privacy: .public) mm \
            of \(measurements.count, privacy: .public) windows: \(windows, privacy: .public))
            """
        )

        return .merge(
            .run { [bleCSCClient] _ in await bleCSCClient.setWheelCircumference(mm) },
            .run { send in
                try await clock.sleep(for: Self.bannerDismissDelay)
                await send(.bannerDismissed)
            }
            .cancellable(id: CancelID.bannerTimer, cancelInFlight: true)
        )
    }
}
