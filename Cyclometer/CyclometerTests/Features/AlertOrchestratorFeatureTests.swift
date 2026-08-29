import Testing
import ComposableArchitecture
import Foundation
@testable import Cyclometer

/// Fixed clock for AlertOrchestratorFeature's timestamped dispatch guard in TestStores.
private let testDate = Date(timeIntervalSince1970: 1_000_000)

/// #155: isolated coverage for the L0–L3 AlertLevel dispatch mechanism, extracted
/// from `ActiveRideFeature` (#135) into its own reducer. These tests drive
/// `AlertOrchestratorFeature` directly via `.alertLevelChanged`/`.hardDisconnected` —
/// no `RadarTarget`/`AlertLevel.level(for:)` derivation involved, since that stays a
/// parent-level concern (see `ActiveRideFeatureAlertEscalationTests`' thin wiring
/// tests for confirmation that the parent forwards into this reducer correctly).
@MainActor
@Suite("AlertOrchestratorFeature")
struct AlertOrchestratorFeatureTests {

    private struct Counts: Sendable {
        var hapticAdvisory = 0, hapticWarning = 0, hapticDanger = 0, hapticAllClear = 0
        var audioWarning = 0, audioDanger = 0, audioAllClear = 0
    }

    private func makeStore(
        clock: TestClock<Duration>,
        counts: LockIsolated<Counts>
    ) -> TestStoreOf<AlertOrchestratorFeature> {
        var haptics = HapticsClient.testValue
        haptics.playAdvisory = { counts.withValue { $0.hapticAdvisory += 1 } }
        haptics.playWarning = { counts.withValue { $0.hapticWarning += 1 } }
        haptics.playDanger = { counts.withValue { $0.hapticDanger += 1 } }
        haptics.playAllClear = { counts.withValue { $0.hapticAllClear += 1 } }

        var audio = AudioClient.testValue
        audio.playWarning = { counts.withValue { $0.audioWarning += 1 } }
        audio.playDanger = { counts.withValue { $0.audioDanger += 1 } }
        audio.playAllClear = { counts.withValue { $0.audioAllClear += 1 } }

        return TestStore(initialState: AlertOrchestratorFeature.State()) {
            AlertOrchestratorFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date = .constant(testDate)
            $0.hapticsClient = haptics
            $0.audioClient = audio
        }
    }

    @Test("L0→L1: haptic advisory fires, no audio (Audio.md: L1 never has a tone)")
    func clearToAdvisory() async {
        let counts = LockIsolated(Counts())
        let store = makeStore(clock: TestClock(), counts: counts)

        await store.send(.alertLevelChanged(.advisory)) {
            $0.activeAlertLevel = .advisory
            $0.lastAlertDispatchAt = [.advisory: testDate]
        }
        #expect(counts.value.hapticAdvisory == 1)
        #expect(counts.value.audioWarning == 0)
        #expect(counts.value.audioDanger == 0)
        #expect(counts.value.audioAllClear == 0)
    }

    @Test("L1→L2: haptic warning and audio warning both fire once")
    func advisoryToCaution() async {
        let counts = LockIsolated(Counts())
        let store = makeStore(clock: TestClock(), counts: counts)

        await store.send(.alertLevelChanged(.advisory)) {
            $0.activeAlertLevel = .advisory
            $0.lastAlertDispatchAt = [.advisory: testDate]
        }

        let secondDate = testDate.addingTimeInterval(AlertOrchestratorFeature.alertReTriggerInterval + 1)
        store.dependencies.date.now = secondDate

        await store.send(.alertLevelChanged(.caution)) {
            $0.activeAlertLevel = .caution
            $0.lastAlertDispatchAt = [.advisory: testDate, .caution: secondDate]
        }
        #expect(counts.value.hapticWarning == 1)
        #expect(counts.value.audioWarning == 1)
    }

    @Test("L2→L3: danger tone begins immediately (not doubled with Warning) and repeats every 800ms while active")
    func cautionToDangerRepeatsThenClears() async {
        let clock = TestClock()
        let counts = LockIsolated(Counts())
        let store = makeStore(clock: clock, counts: counts)

        await store.send(.alertLevelChanged(.caution)) {
            $0.activeAlertLevel = .caution
            $0.lastAlertDispatchAt = [.caution: testDate]
        }
        #expect(counts.value.audioWarning == 1)

        let dangerDate = testDate.addingTimeInterval(AlertOrchestratorFeature.alertReTriggerInterval + 1)
        store.dependencies.date.now = dangerDate
        await store.send(.alertLevelChanged(.danger)) {
            $0.activeAlertLevel = .danger
            $0.lastAlertDispatchAt = [.caution: testDate, .danger: dangerDate]
        }
        #expect(counts.value.hapticDanger == 1)
        #expect(counts.value.audioDanger == 1)   // the loop's first iteration
        #expect(counts.value.audioWarning == 1)  // unchanged — no double alert

        await clock.advance(by: .milliseconds(800))
        #expect(counts.value.audioDanger == 2)
        await clock.advance(by: .milliseconds(800))
        #expect(counts.value.audioDanger == 3)

        // Exit L3 so the repeating effect doesn't leak past the end of the test —
        // also exercises L3→L0 (danger stops, All Clear plays once).
        let clearDate = dangerDate.addingTimeInterval(AlertOrchestratorFeature.alertReTriggerInterval + 1)
        store.dependencies.date.now = clearDate
        await store.send(.alertLevelChanged(.clear)) {
            $0.activeAlertLevel = .clear
            // .danger's stamp is cleared, not carried forward — its loop was just
            // forcibly cancelled by this same transition (see dispatchAlert).
            $0.lastAlertDispatchAt = [.caution: testDate, .clear: clearDate]
        }
        #expect(counts.value.audioAllClear == 1)

        await clock.advance(by: .seconds(5))
        #expect(counts.value.audioDanger == 3)  // unchanged — the loop actually stopped
    }

    @Test("L3→L2: haptic still taps (asymmetric), but Warning tone does NOT re-fire and the danger loop stops")
    func dangerToCautionNoReAlert() async {
        let clock = TestClock()
        let counts = LockIsolated(Counts())
        let store = makeStore(clock: clock, counts: counts)

        await store.send(.alertLevelChanged(.caution)) {
            $0.activeAlertLevel = .caution
            $0.lastAlertDispatchAt = [.caution: testDate]
        }
        #expect(counts.value.hapticWarning == 1)
        #expect(counts.value.audioWarning == 1)

        let dangerDate = testDate.addingTimeInterval(AlertOrchestratorFeature.alertReTriggerInterval + 1)
        store.dependencies.date.now = dangerDate
        await store.send(.alertLevelChanged(.danger)) {
            $0.activeAlertLevel = .danger
            $0.lastAlertDispatchAt = [.caution: testDate, .danger: dangerDate]
        }
        #expect(counts.value.audioDanger == 1)

        let downgradeDate = dangerDate.addingTimeInterval(AlertOrchestratorFeature.alertReTriggerInterval + 1)
        store.dependencies.date.now = downgradeDate
        await store.send(.alertLevelChanged(.caution)) {
            $0.activeAlertLevel = .caution
            // .danger's stamp is cleared, not carried forward — see dispatchAlert.
            $0.lastAlertDispatchAt = [.caution: downgradeDate]
        }
        #expect(counts.value.hapticWarning == 2)  // still fires — haptic is level-only
        #expect(counts.value.audioWarning == 1)   // unchanged — no re-alert on downgrade

        // Confirm the repeating danger loop actually stopped.
        await clock.advance(by: .seconds(5))
        #expect(counts.value.audioDanger == 1)
    }

    @Test("A flap back into danger within the guard window resumes the alert immediately, not muted")
    func dangerFlapResumesImmediately() async {
        let clock = TestClock()
        let counts = LockIsolated(Counts())
        let store = makeStore(clock: clock, counts: counts)

        await store.send(.alertLevelChanged(.danger)) {
            $0.activeAlertLevel = .danger
            $0.lastAlertDispatchAt = [.danger: testDate]
        }
        #expect(counts.value.hapticDanger == 1)
        #expect(counts.value.audioDanger == 1)

        // Dips to caution 0.5s later — the loop is cancelled and its guard stamp
        // cleared (see dispatchAlert's cancel branch). No audio warning here: a
        // danger→caution downgrade never re-alerts (Audio.md, matching
        // dangerToCautionNoReAlert above) — only the level-only haptic fires.
        let cautionDate = testDate.addingTimeInterval(0.5)
        store.dependencies.date.now = cautionDate
        await store.send(.alertLevelChanged(.caution)) {
            $0.activeAlertLevel = .caution
            $0.lastAlertDispatchAt = [.caution: cautionDate]  // .danger entry cleared
        }
        #expect(counts.value.hapticWarning == 1)
        #expect(counts.value.audioWarning == 0)

        // Back to danger only 0.3s later — well inside the 3s guard window. The
        // alert must still resume immediately: it's the same continuing threat,
        // not a fresh re-trigger of a stable level (PRD §8.3: "persists until
        // threat recedes"). Before this fix, the stale `lastAlertDispatchAt[.danger]`
        // from testDate would have blocked this, leaving the rider unalerted
        // mid-threat.
        let backDate = cautionDate.addingTimeInterval(0.3)
        store.dependencies.date.now = backDate
        await store.send(.alertLevelChanged(.danger)) {
            $0.activeAlertLevel = .danger
            $0.lastAlertDispatchAt = [.caution: cautionDate, .danger: backDate]
        }
        #expect(counts.value.hapticDanger == 2)
        #expect(counts.value.audioDanger == 2)  // fired again — not blocked by a stale guard

        await clock.advance(by: .milliseconds(800))
        #expect(counts.value.audioDanger == 3)  // the resumed loop is actually running

        // Exit L3 so the repeating effect doesn't leak past the end of the test.
        let clearDate = backDate.addingTimeInterval(AlertOrchestratorFeature.alertReTriggerInterval + 1)
        store.dependencies.date.now = clearDate
        await store.send(.alertLevelChanged(.clear)) {
            $0.activeAlertLevel = .clear
            $0.lastAlertDispatchAt = [.caution: cautionDate, .clear: clearDate]
        }
    }

    @Test("L2→L0: All Clear tone fires once")
    func cautionToClear() async {
        let counts = LockIsolated(Counts())
        let store = makeStore(clock: TestClock(), counts: counts)

        await store.send(.alertLevelChanged(.caution)) {
            $0.activeAlertLevel = .caution
            $0.lastAlertDispatchAt = [.caution: testDate]
        }

        let clearDate = testDate.addingTimeInterval(AlertOrchestratorFeature.alertReTriggerInterval + 1)
        store.dependencies.date.now = clearDate
        await store.send(.alertLevelChanged(.clear)) {
            $0.activeAlertLevel = .clear
            $0.lastAlertDispatchAt = [.caution: testDate, .clear: clearDate]
        }
        #expect(counts.value.audioAllClear == 1)
    }

    @Test("L1→L0 fires nothing, and does not consume the guard for a genuine L2→L0 that follows")
    func advisoryToClearIsNoOpAndDoesNotBlockLaterAllClear() async {
        let counts = LockIsolated(Counts())
        let store = makeStore(clock: TestClock(), counts: counts)

        await store.send(.alertLevelChanged(.advisory)) {
            $0.activeAlertLevel = .advisory
            $0.lastAlertDispatchAt = [.advisory: testDate]
        }

        // L1 → L0: no state change to lastAlertDispatchAt, no haptic/audio.
        await store.send(.alertLevelChanged(.clear)) {
            $0.activeAlertLevel = .clear
        }
        #expect(counts.value.hapticAllClear == 0)
        #expect(counts.value.audioAllClear == 0)

        // A genuine L2 → L0 moments later must still fire — proving the no-op above
        // didn't stamp a `.clear` guard timestamp that would have blocked this.
        let cautionDate = testDate.addingTimeInterval(1)
        store.dependencies.date.now = cautionDate
        await store.send(.alertLevelChanged(.caution)) {
            $0.activeAlertLevel = .caution
            $0.lastAlertDispatchAt = [.advisory: testDate, .caution: cautionDate]
        }

        let clearDate = cautionDate.addingTimeInterval(1)  // only 1s later — under 3s
        store.dependencies.date.now = clearDate
        await store.send(.alertLevelChanged(.clear)) {
            $0.activeAlertLevel = .clear
            $0.lastAlertDispatchAt = [.advisory: testDate, .caution: cautionDate, .clear: clearDate]
        }
        #expect(counts.value.audioAllClear == 1)
    }

    @Test("Guard blocks a same-level re-trigger within 3s, but allows it after")
    func guardBlocksSameLevelReTriggerWithinThreeSeconds() async {
        let counts = LockIsolated(Counts())
        let store = makeStore(clock: TestClock(), counts: counts)

        await store.send(.alertLevelChanged(.caution)) {
            $0.activeAlertLevel = .caution
            $0.lastAlertDispatchAt = [.caution: testDate]
        }
        #expect(counts.value.audioWarning == 1)

        // Drop to advisory, then flap back to caution 2s after the original caution
        // stamp — still inside the 3s window.
        let advisoryDate = testDate.addingTimeInterval(1)
        store.dependencies.date.now = advisoryDate
        await store.send(.alertLevelChanged(.advisory)) {
            $0.activeAlertLevel = .advisory
            $0.lastAlertDispatchAt = [.caution: testDate, .advisory: advisoryDate]
        }
        #expect(counts.value.hapticAdvisory == 1)

        let backDate = testDate.addingTimeInterval(2)
        store.dependencies.date.now = backDate
        await store.send(.alertLevelChanged(.caution)) {
            $0.activeAlertLevel = .caution
            // Blocked: `.caution` was last dispatched at testDate, only 2s ago —
            // the dict entry (and haptic/audio) does not update.
        }
        #expect(counts.value.hapticWarning == 1)  // unchanged
        #expect(counts.value.audioWarning == 1)   // unchanged — guard blocked the re-trigger

        // Flap again, now past 3s since the original caution stamp.
        let laterAdvisoryDate = testDate.addingTimeInterval(3.1)
        store.dependencies.date.now = laterAdvisoryDate
        await store.send(.alertLevelChanged(.advisory)) {
            $0.activeAlertLevel = .advisory
            // .advisory was last dispatched at advisoryDate (1s in); only 2.1s have
            // passed — also blocked, dict entry unchanged.
        }
        #expect(counts.value.hapticAdvisory == 1)  // unchanged — still guarded

        let laterCautionDate = testDate.addingTimeInterval(4)
        store.dependencies.date.now = laterCautionDate
        await store.send(.alertLevelChanged(.caution)) {
            $0.activeAlertLevel = .caution
            $0.lastAlertDispatchAt = [.caution: laterCautionDate, .advisory: advisoryDate]
        }
        #expect(counts.value.hapticWarning == 2)  // now fires — past the 3s guard
        #expect(counts.value.audioWarning == 2)
    }

    @Test("Hard disconnect while at L3 resets to clear and stops the repeating danger tone, without an All Clear")
    func hardDisconnectDuringDangerStopsRepeatingTone() async {
        let clock = TestClock()
        let counts = LockIsolated(Counts())
        let store = makeStore(clock: clock, counts: counts)

        await store.send(.alertLevelChanged(.danger)) {
            $0.activeAlertLevel = .danger
            $0.lastAlertDispatchAt = [.danger: testDate]
        }
        #expect(counts.value.audioDanger == 1)

        await store.send(.hardDisconnected) {
            $0.activeAlertLevel = .clear
            $0.lastAlertDispatchAt = [:]
        }
        #expect(counts.value.hapticAllClear == 0)
        #expect(counts.value.audioAllClear == 0)

        // Confirm the repeating loop actually stopped.
        await clock.advance(by: .seconds(5))
        #expect(counts.value.audioDanger == 1)
    }

    @Test("A reconnect reporting a fresh danger is not muted by a stale pre-disconnect guard stamp")
    func reconnectAfterDisconnectIsNotMutedByStaleGuard() async {
        let clock = TestClock()
        let counts = LockIsolated(Counts())
        let store = makeStore(clock: clock, counts: counts)

        await store.send(.alertLevelChanged(.danger)) {
            $0.activeAlertLevel = .danger
            $0.lastAlertDispatchAt = [.danger: testDate]
        }
        #expect(counts.value.audioDanger == 1)

        // Hard disconnect 1s later — data loss, not a resolved threat.
        let disconnectDate = testDate.addingTimeInterval(1)
        store.dependencies.date.now = disconnectDate
        await store.send(.hardDisconnected) {
            $0.activeAlertLevel = .clear
            $0.lastAlertDispatchAt = [:]
        }

        // Reconnects 0.5s later, immediately reporting the same vehicle still
        // closing dangerously. Before this fix, the stale `lastAlertDispatchAt[.danger]`
        // from testDate (only 1.5s earlier) would have silently blocked this — a
        // threat the rider was never alerted to post-reconnect.
        let reconnectDate = disconnectDate.addingTimeInterval(0.5)
        store.dependencies.date.now = reconnectDate
        await store.send(.alertLevelChanged(.danger)) {
            $0.activeAlertLevel = .danger
            $0.lastAlertDispatchAt = [.danger: reconnectDate]
        }
        #expect(counts.value.audioDanger == 2)  // fired again — not blocked

        // Exit L3 so the repeating effect doesn't leak past the end of the test.
        await store.send(.hardDisconnected) {
            $0.activeAlertLevel = .clear
            $0.lastAlertDispatchAt = [:]
        }
    }
}
