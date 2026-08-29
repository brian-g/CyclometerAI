import ComposableArchitecture
import Foundation

enum RideRecordingState: Equatable, Sendable {
    case idle, active, paused, ended
}

@Reducer
struct ActiveRideFeature {

    /// Consecutive zero-speed seconds while active before the ride auto-ends.
    /// PRD §8.8: "Auto-end if speed = 0 for > 5 minutes (configurable, default on)".
    static let autoEndZeroSpeedSeconds = 300

    /// Consecutive zero-speed seconds while active before the ride auto-pauses
    /// (S12, #102). Shorter than auto-end on purpose — this is the stoplight case,
    /// not the abandoned-ride case, and it fires first: reaching `.paused` freezes
    /// `zeroSpeedSeconds`, so auto-end cannot trigger from a stop auto-pause already
    /// caught. No PRD-specified threshold exists; chosen to match a brief stop.
    static let autoPauseZeroSpeedSeconds = 10

    /// PRD §8.3 "Alert Rules": minimum gap between re-firing the same alert level.
    static let alertReTriggerInterval: TimeInterval = 3

    @Dependency(\.continuousClock) var clock
    @Dependency(\.bleHRClient) var bleHRClient
    @Dependency(\.variaRadarClient) var variaRadarClient
    @Dependency(\.hapticsClient) var hapticsClient
    @Dependency(\.audioClient) var audioClient
    @Dependency(\.locationClient) var locationClient
    @Dependency(\.permissionsClient) var permissionsClient
    @Dependency(\.date.now) var now

    @ObservableState
    struct State: Equatable {
        var recordingState: RideRecordingState = .idle
        var elapsedSeconds: Int = 0
        var speedKPH: Double = 0
        var heartRateBPM: Int = 0
        var hrZone: Int = 0
        var isHRPaired: Bool = false
        var cadence = CadenceFeature.State()
        var distanceMeters: Double = 0
        var distanceKM: Double { distanceMeters / 1000.0 }
        /// The rider's HR overrides (#96). Read-only here — the dashboard derives
        /// zones from the profile but never edits it; that is Settings' job.
        ///
        /// Zones resolve from this on each reading rather than from a seeded copy, so
        /// a profile edit needs no lifecycle action. Max and resting were hardcoded
        /// to 190/55 before #96, which disagreed with the 60 that DataModel.md §3.5
        /// has always specified as the resting default.
        @SharedReader(.riderProfile) var riderProfile
        /// Read-only here — Settings owns the write side (#102). Consulted for
        /// `isAutoPauseEnabled`.
        @SharedReader(.appPreferences) var preferences
        var speed = SpeedFeature.State()
        var calibration = WheelCalibrationFeature.State()
        var maxSpeedKPH: Double = 0
        var speedSampleCount: Int = 0
        var speedSampleSum: Double = 0
        var averageSpeedKPH: Double {
            speedSampleCount > 0 ? speedSampleSum / Double(speedSampleCount) : 0
        }
        // Canonical m/s views of the speed stats for consumers (e.g. SpeedWidget)
        // that convert to display units themselves. Uses Measurement so the
        // KPH→MPS factor isn't hardcoded at the call site.
        var speedMPS: Double {
            Measurement(value: speedKPH, unit: UnitSpeed.kilometersPerHour)
                .converted(to: .metersPerSecond).value
        }
        var averageSpeedMPS: Double {
            Measurement(value: averageSpeedKPH, unit: UnitSpeed.kilometersPerHour)
                .converted(to: .metersPerSecond).value
        }
        var maxSpeedMPS: Double {
            Measurement(value: maxSpeedKPH, unit: UnitSpeed.kilometersPerHour)
                .converted(to: .metersPerSecond).value
        }
        var isRadarPaired: Bool = false
        var radarTargets: [RadarTarget] = []
        /// Raw BLE lifecycle, mirrors CadenceFeature/SpeedFeature's `connectionState`
        /// field. `isRadarPaired` stays as-is (it gates the haptic-timer logic) —
        /// this is purely for the sidebar's visible/offline presentation (#137).
        var radarConnectionState: VariaRadarClient.ConnectionState = .disconnected
        /// True for the rest of this ride once radar has ever gone `.active`. Lets
        /// the sidebar distinguish "never paired" (hidden, no space reserved) from
        /// "was paired, lost signal" (grayed, space stays reserved) (#137).
        var wasRadarEverPaired: Bool = false
        var isRadarSidebarVisible: Bool { wasRadarEverPaired }
        var isRadarOffline: Bool { wasRadarEverPaired && radarConnectionState != .active }
        /// Ride-level escalation derived from `radarTargets` (PRD §8.3) — distinct
        /// from any single vehicle's `ThreatLevel` dot color. Exposed for the
        /// screen-effects and radar-offline-indicator work in companion issues.
        var activeAlertLevel: AlertLevel = .clear
        /// Per-level timestamp of the last haptic/audio dispatch, backing the
        /// minimum-3s same-level re-trigger guard (PRD §8.3 "Alert Rules").
        var lastAlertDispatchAt: [AlertLevel: Date] = [:]
        var coordinate: Coordinate? = nil
        var trackCoordinates: [Coordinate] = []
        var altitude: Double = 0
        var heading: Double = -1
        var horizontalAccuracy: Double = 0
        var isLocationAvailable: Bool = false
        var zeroSpeedSeconds: Int = 0
        var isAutoEndEnabled: Bool = true
        /// Whether the *current* pause was auto-triggered rather than a manual Pause
        /// tap — the only kind motion is allowed to auto-resume (#102).
        var isAutoPaused: Bool = false
        /// Wheel auto-calibration stands down while the rider has something more
        /// urgent to attend to, and whenever the ride isn't actively recording — a
        /// paused ride still receives GPS fixes, and stationary scatter would poison
        /// the window (PRD §8.9).
        var isCalibrationSuspended: Bool {
            recordingState != .active || radarTargets.contains { $0.threatLevel != .allClear }
        }
        /// Reads through to `AppPreferences.preferredUnit` — mirrors
        /// `SettingsFeature.State.preferredUnit` so a Settings toggle propagates
        /// immediately to every dashboard widget with no lifecycle action needed.
        var unitSystem: UnitSystem { preferences.preferredUnit }
        @Presents var finishAlert: AlertState<Action.FinishAlert>?
        var isPaused: Bool { recordingState == .paused }
    }

    enum Action: Equatable {
        case task
        case pauseTapped
        case resumeTapped
        case finishTapped
        case finishAlert(PresentationAction<FinishAlert>)
        case autoEndTriggered
        case autoPauseTriggered
        case heartRateUpdated(Int)
        case hrPairingChanged(Bool)
        case cadence(CadenceFeature.Action)
        case elapsedTick
        case radarTargetsUpdated([RadarTarget])
        case radarConnectionChanged(VariaRadarClient.ConnectionState)
        case radarReconnectTimedOut
        case speed(SpeedFeature.Action)
        case calibration(WheelCalibrationFeature.Action)
        case locationUpdated(LocationUpdate)
        case locationAuthorizationResult(PermissionState)

        @CasePathable
        enum FinishAlert: Equatable {
            case confirmFinish
        }
    }

    private enum CancelID { case radarLossTimer, dangerAudioRepeat }

    var body: some ReducerOf<Self> {
        Scope(state: \.speed, action: \.speed) {
            SpeedFeature()
        }
        Scope(state: \.cadence, action: \.cadence) {
            CadenceFeature()
        }
        Scope(state: \.calibration, action: \.calibration) {
            WheelCalibrationFeature()
        }
        Reduce { state, action in
            switch action {
            case .task:
                state.recordingState = .active
                return .merge(
                    .send(.speed(.startListening)),
                    .send(.cadence(.startListening)),
                    .send(.calibration(.startListening)),
                    .run { send in
                        for await _ in clock.timer(interval: .seconds(1)) {
                            await send(.elapsedTick)
                        }
                    },
                    .run { [bleHRClient] send in
                        await bleHRClient.startScanning()
                        for await bpm in bleHRClient.heartRate() {
                            await send(.heartRateUpdated(bpm))
                        }
                    },
                    .run { [bleHRClient] send in
                        for await paired in bleHRClient.pairingStatus() {
                            await send(.hrPairingChanged(paired))
                        }
                    },
                    .run { [variaRadarClient] send in
                        await variaRadarClient.startScanning()
                        for await targets in variaRadarClient.radarTargets() {
                            await send(.radarTargetsUpdated(targets))
                        }
                    },
                    .run { [variaRadarClient] send in
                        for await connectionState in variaRadarClient.connectionState() {
                            await send(.radarConnectionChanged(connectionState))
                        }
                    },
                    .run { [locationClient, permissionsClient] send in
                        let status = await permissionsClient.request(.locationWhenInUse)
                        await send(.locationAuthorizationResult(status))
                        guard status.isGranted else { return }
                        for await update in locationClient.startUpdates() {
                            await send(.locationUpdated(update))
                        }
                        await locationClient.stopUpdates()
                    }
                )
            case .pauseTapped:
                guard state.recordingState == .active else { return .none }
                state.recordingState = .paused
                return .none
            case .resumeTapped:
                guard state.recordingState == .paused else { return .none }
                state.recordingState = .active
                state.zeroSpeedSeconds = 0
                state.isAutoPaused = false
                return .none
            case .finishTapped:
                guard state.recordingState == .paused else { return .none }
                state.finishAlert = AlertState {
                    TextState("Finish Ride")
                } actions: {
                    ButtonState(role: .destructive, action: .confirmFinish) {
                        TextState("Finish")
                    }
                    ButtonState(role: .cancel) {
                        TextState("Cancel")
                    }
                }
                return .none
            case .finishAlert(.presented(.confirmFinish)):
                state.recordingState = .ended
                return .run { [bleHRClient, variaRadarClient, locationClient] _ in
                    async let hr: Void = bleHRClient.disconnect()
                    async let radar: Void = variaRadarClient.disconnect()
                    async let loc: Void = locationClient.stopUpdates()
                    _ = await (hr, radar, loc)
                }
            case .finishAlert:
                return .none
            case .autoEndTriggered:
                guard state.recordingState == .active else { return .none }
                state.recordingState = .paused
                return .send(.finishTapped)
            case .autoPauseTriggered:
                guard state.recordingState == .active else { return .none }
                state.recordingState = .paused
                state.isAutoPaused = true
                return .none
            case .heartRateUpdated(let bpm):
                state.heartRateBPM = bpm
                // Through the profile's own facade rather than unpacking it into
                // maxHR/restingHR here — M5's HealthKit terms then thread through one
                // place instead of every call site that re-assembles the pair.
                state.hrZone = state.riderProfile.zone(forBPM: bpm).rawValue
                return .none
            case .hrPairingChanged(let paired):
                state.isHRPaired = paired
                if !paired {
                    state.heartRateBPM = 0
                    state.hrZone = 0
                }
                return .none
            case .cadence:
                return .none
            case .elapsedTick:
                guard state.recordingState == .active else { return .none }
                state.elapsedSeconds += 1
                state.distanceMeters += max(state.speed.speedMPS ?? 0, 0)
                if (state.speed.speedMPS ?? 0) == 0 {
                    state.zeroSpeedSeconds += 1
                } else {
                    state.zeroSpeedSeconds = 0
                }
                if state.preferences.isAutoPauseEnabled, state.zeroSpeedSeconds >= Self.autoPauseZeroSpeedSeconds {
                    return .send(.autoPauseTriggered)
                }
                if state.isAutoEndEnabled, state.zeroSpeedSeconds >= Self.autoEndZeroSpeedSeconds {
                    return .send(.autoEndTriggered)
                }
                return .none
            case .radarTargetsUpdated(let targets):
                state.radarTargets = targets
                let newLevel = AlertLevel.level(for: targets)
                guard newLevel != state.activeAlertLevel else { return .none }
                let previous = state.activeAlertLevel
                state.activeAlertLevel = newLevel
                return dispatchAlert(&state, level: newLevel, previous: previous)
            case .radarConnectionChanged(let connectionState):
                state.radarConnectionState = connectionState
                switch connectionState {
                case .active:
                    state.isRadarPaired = true
                    state.wasRadarEverPaired = true
                    return .cancel(id: CancelID.radarLossTimer)
                case .reconnecting:
                    // Badge stays paired during the 10s grace window (PRD §9.1);
                    // only arm the timer while paired so the haptic fires once.
                    guard state.isRadarPaired else { return .none }
                    return .run { send in
                        try await clock.sleep(for: .seconds(10))
                        await send(.radarReconnectTimedOut)
                    }
                    .cancellable(id: CancelID.radarLossTimer, cancelInFlight: true)
                case .disconnected:
                    state.isRadarPaired = false
                    state.radarTargets = []
                    // A hard unpair is data loss, not a resolved threat — reset
                    // silently (no All Clear tone) and stop any in-flight danger
                    // loop rather than leave it repeating with no data feeding it.
                    // Every re-trigger guard stamp is cleared too: without this, a
                    // reconnect that reports a fresh, genuine threat could be
                    // silently muted by a timestamp left over from before the data
                    // feed was lost — the alert context doesn't survive the outage.
                    state.activeAlertLevel = .clear
                    state.lastAlertDispatchAt = [:]
                    return .merge(
                        .cancel(id: CancelID.radarLossTimer),
                        .cancel(id: CancelID.dangerAudioRepeat)
                    )
                default:
                    return .none
                }
            case .radarReconnectTimedOut:
                state.isRadarPaired = false
                state.radarConnectionState = .disconnected
                state.radarTargets = []
                // Routed through the same guarded dispatch path as vehicle-based
                // escalation (#135) rather than firing unconditionally — no `!=`
                // guard here, since disconnect is a distinct real-world trigger
                // that must always attempt to fire, same as before. This means a
                // rapidly flapping BLE link can have its L1 haptic suppressed by
                // the 3s guard even though PRD §8.2 reads as unconditional
                // ("Disconnection... triggers L1 advisory haptic") — a deliberate
                // product choice (favor one haptic over a spam of them for a
                // flapping connection) over a literal reading of that line; PRD
                // §8.3's general Alert Rules apply the same guard everywhere else.
                let previous = state.activeAlertLevel
                state.activeAlertLevel = .advisory
                return dispatchAlert(&state, level: .advisory, previous: previous)
            case .locationUpdated(let update):
                state.coordinate = update.coordinate
                // Only record track points while actively riding, so paused/stopped
                // GPS jitter doesn't pollute the polyline — mirrors distanceMeters,
                // which also only accumulates while active (.elapsedTick).
                if state.recordingState == .active {
                    state.trackCoordinates.append(update.coordinate)
                }
                state.altitude = update.altitude
                state.heading = update.heading
                state.horizontalAccuracy = update.horizontalAccuracy
                let kph = max(update.speed, 0) * 3.6
                state.speedKPH = kph
                if kph > 0 {
                    state.speedSampleCount += 1
                    state.speedSampleSum += kph
                }
                if kph > state.maxSpeedKPH { state.maxSpeedKPH = kph }
                return .merge(
                    .send(.speed(.gpsSpeedReceived(update.speed))),
                    .send(.calibration(.locationUpdated(update)))
                )
            case .locationAuthorizationResult(let status):
                state.isLocationAvailable = status.isGranted
                return .none
            case .speed:
                // Only a pause auto-pause itself made is eligible to auto-resume — a
                // rider who tapped Pause has to tap Resume (#102).
                if state.isAutoPaused, (state.speed.speedMPS ?? 0) > 0 {
                    state.recordingState = .active
                    state.isAutoPaused = false
                    state.zeroSpeedSeconds = 0
                }
                return .none
            case .calibration:
                return .none
            }
        }
        // Radar targets arrive continuously and recording state changes from five
        // places, but suspension itself flips rarely — so it is forwarded on the
        // transition rather than on every input that feeds it.
        .onChange(of: \.isCalibrationSuspended) { _, isSuspended in
            Reduce { _, _ in
                .send(.calibration(.suspensionChanged(isSuspended)))
            }
        }
        .ifLet(\.$finishAlert, action: \.finishAlert)
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
