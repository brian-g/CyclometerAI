import ComposableArchitecture
import Foundation
import os

// Stream live: Console.app / Xcode console, filter subsystem "com.xavier.cyclometer".
private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "alerts")

@Reducer
struct AlertOrchestratorFeature {

    /// PRD §8.3 "Alert Rules": minimum gap between re-firing the same alert level.
    static let alertReTriggerInterval: TimeInterval = 3

    @Dependency(\.continuousClock) var clock
    @Dependency(\.hapticsClient) var hapticsClient
    @Dependency(\.audioClient) var audioClient
    @Dependency(\.date.now) var now

    @ObservableState
    struct State: Equatable {
        /// Ride-level escalation derived from `radarTargets` (PRD §8.3) — distinct
        /// from any single vehicle's `ThreatLevel` dot color. Exposed for the
        /// screen-effects and radar-offline-indicator work in companion issues.
        var activeAlertLevel: AlertLevel = .clear
        /// Per-level timestamp of the last haptic/audio dispatch, backing the
        /// minimum-3s same-level re-trigger guard (PRD §8.3 "Alert Rules").
        var lastAlertDispatchAt: [AlertLevel: Date] = [:]
    }

    enum Action: Equatable {
        /// A new level to transition to — sent whenever `ActiveRideFeature` decides a
        /// dispatch attempt is warranted (either the derived level actually changed, or
        /// a reconnect timeout forces one unconditionally; see its call sites).
        case alertLevelChanged(AlertLevel)
        /// A hard radar unpair: data loss, not a resolved threat.
        case hardDisconnected
        /// A turn navigation has just announced (#198). Its own action, never an
        /// `alertLevelChanged`: `activeAlertLevel` also drives the radar sidebar and calibration
        /// suspension, and a turn is not a threat.
        case turnAnnounced(Maneuver.Direction)
    }

    private enum CancelID { case dangerAudioRepeat }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .alertLevelChanged(let level):
                let previous = state.activeAlertLevel
                state.activeAlertLevel = level
                return dispatchAlert(&state, level: level, previous: previous)

            case .hardDisconnected:
                // A hard unpair is data loss, not a resolved threat — reset silently
                // (no All Clear tone) and stop any in-flight danger loop rather than
                // leave it repeating with no data feeding it. Every re-trigger guard
                // stamp is cleared too: without this, a reconnect that reports a
                // fresh, genuine threat could be silently muted by a timestamp left
                // over from before the data feed was lost — the alert context doesn't
                // survive the outage.
                state.activeAlertLevel = .clear
                state.lastAlertDispatchAt = [:]
                return .cancel(id: CancelID.dangerAudioRepeat)

            case .turnAnnounced(let direction):
                return turnTone(direction, state)
            }
        }
    }

    // MARK: - Turn tones

    /// The turn's tone, unless radar has the speaker (#198). Radar wins wherever both would sound:
    /// throughout L3, whose burst repeats until the threat recedes, and while a Warning is still
    /// sounding. Not for the rest of an L2 — the Warning plays once, on entry, and L2 can hold for
    /// much of a busy road, which is where turns are hardest to find. A held tone is dropped, not
    /// replayed; the turn instruction still shows. A radar tone that starts mid-turn-tone cuts it
    /// off (`AudioEngineState.play`), so radar wins that way round too.
    ///
    /// The Warning is timed from its dispatch stamp, which an L3 → L2 downgrade also sets, with no
    /// tone of its own. Holding the turn tone then as well keeps it off a danger burst still
    /// trailing the loop's cancellation.
    private func turnTone(_ direction: Maneuver.Direction, _ state: State) -> Effect<Action> {
        let now = self.now  // read once, as in dispatchAlert
        let isWarningSounding = state.lastAlertDispatchAt[.caution]
            .map { now.timeIntervalSince($0) < ToneKind.warning.duration } ?? false
        guard state.activeAlertLevel != .danger, !isWarningSounding else {
            let reason = state.activeAlertLevel == .danger ? "radar at L3" : "Warning sounding"
            logger.notice("turn tone held — \(reason, privacy: .public)")
            return .none
        }
        logger.notice("turn tone — \(String(describing: direction), privacy: .public)")
        // Default priority: PRD §8.6's ±10 m is a second at 40 km/h, not radar's 200 ms.
        return .run { [audioClient] _ in
            await audioClient.playTurn(direction)
        }
    }

    // MARK: - Alert escalation dispatch

    /// Builds the haptic + audio effect(s) for a transition into `level` from
    /// `previous`, generalizing `Audio.md`'s "Tone Relationships and Progression"
    /// table (which only documents adjacent-level pairs) to skip-level jumps: haptic
    /// is purely a function of the new level (PRD §8.3's table is level-keyed, not
    /// transition-keyed); audio keys off `(level, previous)` with exactly the two
    /// non-default branches the table calls out.
    private func dispatchAlert(_ state: inout State, level: AlertLevel, previous: AlertLevel) -> Effect<Action> {
        var effects: [Effect<Action>] = []

        if previous == .danger, level != .danger {
            // Stops the loop's ContinuousClock.sleep promptly. A danger tone already
            // mid-playback can trail up to ~580ms on real hardware — AudioClient's
            // completion continuation isn't cancellation-aware — which is bounded and
            // an acceptable failure mode (finishes an alert rather than truncating one).
            effects.append(.cancel(id: CancelID.dangerAudioRepeat))
            // The loop was forcibly cut off here, not left to finish naturally — clear
            // its guard stamp too. Otherwise a flap back into .danger within the 3s
            // window (sensor noise around the threshold, or a brief reconnect) would
            // silently mute an active, continuing threat for up to 3s, since the guard
            // below can't otherwise distinguish "still the same ongoing alert, just
            // interrupted" from "a separate re-trigger of a stable level" — PRD §8.3:
            // "L3 alert persists until threat recedes."
            state.lastAlertDispatchAt[.danger] = nil
        }

        // L1→L0 is the sole no-op transition (L0 has no haptic; Audio.md explicitly
        // exempts L1 from ever having a tone). Every other pair always fires at least
        // the haptic, so this is the only case that must bypass the guard entirely —
        // otherwise stamping `lastAlertDispatchAt[.clear]` here would wrongly block a
        // genuine L2→L0/L3→L0 All Clear tone that follows soon after.
        let isNoOpTransition = level == .clear && previous == .advisory

        let now = self.now  // read once — an .incrementing test clock must see one value
        let isReTriggerGuarded = state.lastAlertDispatchAt[level]
            .map { now.timeIntervalSince($0) < Self.alertReTriggerInterval } ?? false

        if !isNoOpTransition && !isReTriggerGuarded {
            state.lastAlertDispatchAt[level] = now

            effects.append(.run(priority: .userInteractive) { [hapticsClient] _ in
                switch level {
                case .clear: break
                case .advisory: await hapticsClient.playAdvisory()
                case .caution: await hapticsClient.playWarning()
                // L3→L2 still fires this double-tap — Audio.md's "downgrade is not
                // re-alerted" rule is scoped to the *tone*, not the haptic.
                case .danger: await hapticsClient.playDanger()
                }
            })

            switch (level, previous) {
            case (.caution, .danger):
                break  // downgrade — Audio.md: "Warning tone does NOT play"
            case (.caution, _):
                effects.append(.run(priority: .userInteractive) { [audioClient] _ in
                    await audioClient.playWarning()
                })
            case (.clear, .caution), (.clear, .danger):
                effects.append(.run(priority: .userInteractive) { [audioClient] _ in
                    await audioClient.playAllClear()
                })
            case (.danger, _):
                // The loop's first iteration IS the "begins immediately" tone — a
                // separate one-shot playDanger() here would race it (both call
                // AudioEngineState.play, which stop()s the node on entry, glitching
                // whichever call loses the race).
                effects.append(
                    .run(priority: .userInteractive) { [audioClient, clock] _ in
                        while true {
                            await audioClient.playDanger()
                            try await clock.sleep(for: .milliseconds(800))
                        }
                    }
                    .cancellable(id: CancelID.dangerAudioRepeat, cancelInFlight: true)
                )
            default:
                break  // .advisory never has a tone (Audio.md), regardless of direction
            }
        }

        return effects.isEmpty ? .none : .merge(effects)
    }
}
