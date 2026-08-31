import ComposableArchitecture
import Foundation

enum RideRecordingState: Equatable, Sendable {
    case idle, active, paused, ended
}

/// The dashboard's active HR source (#161). BLE always wins when both are present;
/// see `ActiveRideFeature.State.hrSource`.
enum HRSource: Equatable, Sendable {
    case none, bleStrap, healthKit
}

/// A HealthKit HR reading plus when it arrived, so a reading that's gone stale can be
/// told apart from a fresh one (#161). Bundled into one Optional rather than two
/// separately-nullable fields — a bpm and a timestamp that must always be set or
/// cleared together are one invariant as a struct instead of two to keep in sync.
struct HealthKitHRSample: Equatable, Sendable {
    let bpm: Int
    let receivedAt: Date
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

    /// How old a HealthKit HR sample can be and still count as "live" (#161).
    /// `HealthKitClient.heartRateStream()`'s own doc comment: outside an active workout
    /// the Watch's HR writes land minutes apart, so this can't be tight enough to
    /// require near-continuous samples without defeating the fallback's entire point —
    /// but it still has to reject a reading old enough that showing it as current would
    /// mislead the rider. Five minutes is the balance chosen between those two.
    static let healthKitHRStalenessWindow: TimeInterval = 5 * 60

    @Dependency(\.continuousClock) var clock
    @Dependency(\.bleHRClient) var bleHRClient
    @Dependency(\.variaRadarClient) var variaRadarClient
    @Dependency(\.locationClient) var locationClient
    @Dependency(\.permissionsClient) var permissionsClient
    @Dependency(\.healthKitClient) var healthKitClient
    @Dependency(\.date) var date
    @Dependency(\.uuid) var uuid
    @Dependency(\.persistenceClient) var persistenceClient

    @ObservableState
    struct State: Equatable {
        /// Placeholder until `.task` overwrites it with a fresh, deterministic id
        /// (`@Dependency(\.uuid)`) — mirrors how `recordingState` defaults to `.idle`
        /// pre-start. The persisted Ride record is created with this same id (#171).
        var rideId: UUID = UUID()
        var recordingState: RideRecordingState = .idle
        var elapsedSeconds: Int = 0
        var speedKPH: Double = 0
        var heartRateBPM: Int = 0
        var hrZone: Int = 0
        /// Count of non-zero bpm readings applied to `heartRateBPM`, paired with
        /// `hrSampleSum` — mirrors `speedSampleCount`/`speedSampleSum` (#171).
        var hrSampleCount: Int = 0
        var hrSampleSum: Double = 0
        var maxHeartRateBPM: Int = 0
        var isHRPaired: Bool = false
        /// HealthKit-resolved terms fetched once at ride start (#160), threaded into
        /// every `riderProfile` resolver call below instead of the defaulted `nil`.
        var healthRestingBPM: Int? = nil
        var healthMaxBPM: Int? = nil
        /// Live HR shadow value from HealthKit (#161), kept fresh even while BLE is
        /// the displayed source — mirrors `SpeedFeature.State.latestGPSSpeedMPS` — so a
        /// BLE disconnect has something to promote to immediately. `nil` both when
        /// nothing has arrived yet and once a sample ages out (see
        /// `healthKitHRStalenessWindow`) — the two are indistinguishable from here on
        /// out, which is correct: neither is safe to show as a live reading.
        var healthKitHRSample: HealthKitHRSample? = nil
        /// Computed, not stored: every existing `State(...)` literal that sets
        /// `heartRateBPM`/`isHRPaired` without knowing about this field keeps deriving
        /// the right answer, and the value can never drift out of sync with the two
        /// fields it reads.
        var hrSource: HRSource {
            if isHRPaired { return .bleStrap }
            if healthKitHRSample != nil { return .healthKit }
            return .none
        }
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
        var alertOrchestrator = AlertOrchestratorFeature.State()
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
        case healthProfileFetched(restingBPM: Int?, maxBPM: Int?)
        case healthKitHeartRateUpdated(Int)
        case cadence(CadenceFeature.Action)
        case elapsedTick
        case radarTargetsUpdated([RadarTarget])
        case radarConnectionChanged(VariaRadarClient.ConnectionState)
        case radarReconnectTimedOut
        case alertOrchestrator(AlertOrchestratorFeature.Action)
        case speed(SpeedFeature.Action)
        case calibration(WheelCalibrationFeature.Action)
        case locationUpdated(LocationUpdate)
        case locationAuthorizationResult(PermissionState)

        @CasePathable
        enum FinishAlert: Equatable {
            case confirmFinish
        }
    }

    private enum CancelID { case radarLossTimer, rideCheckpoint }

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
        Scope(state: \.alertOrchestrator, action: \.alertOrchestrator) {
            AlertOrchestratorFeature()
        }
        Reduce { state, action in
            switch action {
            case .task:
                state.recordingState = .active
                state.rideId = uuid()
                let rideId = state.rideId
                let startedAt = date.now
                return .merge(
                    .send(.speed(.startListening)),
                    .send(.cadence(.startListening)),
                    .send(.calibration(.startListening)),
                    .run { [persistenceClient] _ in
                        try? await persistenceClient.createRide(rideId, startedAt)
                    },
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
                    .run { [healthKitClient, date] send in
                        async let restingBPM = try? healthKitClient.fetchRestingHeartRate()
                        async let dob = try? healthKitClient.fetchDateOfBirth()
                        let maxBPM = RiderProfile.estimatedMaxBPM(fromDateOfBirth: await dob, on: date.now)
                        await send(.healthProfileFetched(restingBPM: await restingBPM, maxBPM: maxBPM))
                    },
                    .run { [healthKitClient] send in
                        for await bpm in healthKitClient.heartRateStream() {
                            await send(.healthKitHeartRateUpdated(bpm))
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
                let update = makeRideSummaryUpdate(from: state)
                return .run { [persistenceClient] _ in
                    try? await persistenceClient.updateRideSummary(update)
                }
            case .resumeTapped:
                guard state.recordingState == .paused else { return .none }
                state.recordingState = .active
                state.zeroSpeedSeconds = 0
                state.isAutoPaused = false
                let update = makeRideSummaryUpdate(from: state)
                return .run { [persistenceClient] _ in
                    try? await persistenceClient.updateRideSummary(update)
                }
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
                let rideId = state.rideId
                let endedAt = date.now
                let finalSummary = makeRideSummaryUpdate(from: state)
                return .merge(
                    // A checkpoint queued or in flight from the same tick that just
                    // finished the ride must not land after this write and stomp the
                    // final aggregates with a stale, smaller snapshot.
                    .cancel(id: CancelID.rideCheckpoint),
                    .run { [bleHRClient, variaRadarClient, locationClient] _ in
                        async let hr: Void = bleHRClient.disconnect()
                        async let radar: Void = variaRadarClient.disconnect()
                        async let loc: Void = locationClient.stopUpdates()
                        _ = await (hr, radar, loc)
                    },
                    .run { [persistenceClient] _ in
                        try? await persistenceClient.finalizeRide(rideId, endedAt, finalSummary)
                    }
                )
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
                applyHeartRateReading(bpm, to: &state)
                return .none
            case .hrPairingChanged(let paired):
                state.isHRPaired = paired
                guard !paired else { return .none }
                // BLE is gone — promote whatever HealthKit shadow value is already on
                // hand immediately (#161). There is no grace window to wait out here:
                // unlike `BLECSCClient.connectionState()`, `bleHRClient.pairingStatus()`
                // has no `.reconnecting` substate — `false` is already the fully
                // committed "strap is gone now" signal.
                expireStaleHealthKitSample(in: &state)
                if let sample = state.healthKitHRSample {
                    applyHeartRateReading(sample.bpm, to: &state)
                } else {
                    state.heartRateBPM = 0
                    state.hrZone = 0
                }
                return .none
            case .healthProfileFetched(let restingBPM, let maxBPM):
                state.healthRestingBPM = restingBPM
                state.healthMaxBPM = maxBPM
                return .none
            case .healthKitHeartRateUpdated(let bpm):
                // A HealthKit sample can never legitimately be ≤0 bpm; guarding at
                // ingestion (rather than wherever `healthKitHRSample` is later read)
                // keeps every downstream reader — the disconnect fallback above included
                // — from having to re-derive "0 isn't a real reading" on its own.
                guard bpm > 0 else { return .none }
                state.healthKitHRSample = HealthKitHRSample(bpm: bpm, receivedAt: date.now)
                // BLE has priority (PRD §8.4); while paired, this is a silent shadow
                // update that doesn't touch the displayed reading — mirrors
                // SpeedFeature.gpsSpeedReceived's identical BLE-vs-GPS guard.
                guard !state.isHRPaired else { return .none }
                applyHeartRateReading(bpm, to: &state)
                return .none
            case .cadence:
                return .none
            case .elapsedTick:
                // The SwiftData checkpoint below piggybacks on this guard for its own
                // "only while active" gating — a guard added here for an unrelated
                // reason (e.g. a new sensor check) changes how often, or whether,
                // rides get checkpointed. See the comment at the checkpoint site.
                guard state.recordingState == .active else { return .none }
                // A HealthKit-derived reading can go stale while it's the one on
                // screen, with no disconnect event to catch it — piggyback the check
                // on this once-a-second tick rather than adding a second timer (#161).
                expireStaleHealthKitSample(in: &state)
                if !state.isHRPaired, state.healthKitHRSample == nil {
                    state.heartRateBPM = 0
                    state.hrZone = 0
                }
                state.elapsedSeconds += 1
                state.distanceMeters += max(state.speed.speedMPS ?? 0, 0)
                if (state.speed.speedMPS ?? 0) == 0 {
                    state.zeroSpeedSeconds += 1
                } else {
                    state.zeroSpeedSeconds = 0
                }

                var effects: [Effect<Action>] = []

                // DataModel.md §1 Checkpoint Policy: SwiftData Ride summary update
                // every 30s of active recording — a parallel, independent cadence
                // from the CoreData TrackPoint flush timer (#170). Piggybacked on
                // this 1Hz tick rather than a second Clock timer; the guard above
                // already gives "excludes paused intervals" for free. Cancellable so
                // ride-end can cancel a checkpoint that's queued or still in flight
                // (`.cancel(id: CancelID.rideCheckpoint)` in `.finishAlert`) rather
                // than let a stale write land after the final one.
                if state.elapsedSeconds % 30 == 0 {
                    let update = makeRideSummaryUpdate(from: state)
                    effects.append(
                        .run { [persistenceClient] _ in
                            try? await persistenceClient.updateRideSummary(update)
                        }
                        .cancellable(id: CancelID.rideCheckpoint, cancelInFlight: true)
                    )
                }

                if state.preferences.isAutoPauseEnabled, state.zeroSpeedSeconds >= Self.autoPauseZeroSpeedSeconds {
                    effects.append(.send(.autoPauseTriggered))
                } else if state.isAutoEndEnabled, state.zeroSpeedSeconds >= Self.autoEndZeroSpeedSeconds {
                    effects.append(.send(.autoEndTriggered))
                }

                return effects.isEmpty ? .none : .merge(effects)
            case .radarTargetsUpdated(let targets):
                state.radarTargets = targets
                let newLevel = AlertLevel.level(for: targets)
                guard newLevel != state.alertOrchestrator.activeAlertLevel else { return .none }
                return .send(.alertOrchestrator(.alertLevelChanged(newLevel)))
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
                    return .merge(
                        .cancel(id: CancelID.radarLossTimer),
                        .send(.alertOrchestrator(.hardDisconnected))
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
                return .send(.alertOrchestrator(.alertLevelChanged(.advisory)))
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
            case .alertOrchestrator:
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

    /// Applies a resolved bpm reading — from either source — to the displayed state.
    /// Through the profile's own facade rather than unpacking it into maxHR/restingHR
    /// here — M5's HealthKit terms then thread through one place instead of every call
    /// site that re-assembles the pair. Factored out (#161) so BLE, HealthKit, and the
    /// disconnect fallback can never derive the zone differently by accident.
    private func applyHeartRateReading(_ bpm: Int, to state: inout State) {
        state.heartRateBPM = bpm
        state.hrZone = state.riderProfile.zone(
            forBPM: bpm,
            healthResting: state.healthRestingBPM,
            healthMax: state.healthMaxBPM
        ).rawValue
        if bpm > 0 {
            state.hrSampleCount += 1
            state.hrSampleSum += Double(bpm)
        }
        if bpm > state.maxHeartRateBPM {
            state.maxHeartRateBPM = bpm
        }
    }

    /// Snapshot of the current running aggregates, written to the persisted Ride
    /// both at the 30s checkpoint and at ride end (#171). Gated on sample *count*,
    /// not "value > 0" — a genuine 0 bpm/rpm max would otherwise be misreported as
    /// "no data."
    private func makeRideSummaryUpdate(from state: State) -> RideSummaryUpdate {
        let recordingState: Ride.RecordingState = switch state.recordingState {
        case .paused: .paused
        case .ended: .ended
        case .active, .idle: .active
        }
        return RideSummaryUpdate(
            rideId: state.rideId,
            recordingState: recordingState,
            durationSeconds: TimeInterval(state.elapsedSeconds),
            distanceMeters: state.distanceMeters,
            averageSpeedMPS: state.averageSpeedMPS,
            maxSpeedMPS: state.maxSpeedMPS,
            averageHeartRateBPM: state.hrSampleCount > 0
                ? Int((state.hrSampleSum / Double(state.hrSampleCount)).rounded()) : nil,
            maxHeartRateBPM: state.hrSampleCount > 0 ? state.maxHeartRateBPM : nil,
            averageCadenceRPM: state.cadence.pedalingSampleCount > 0
                ? state.cadence.averageCadenceRPM : nil,
            maxCadenceRPM: state.cadence.pedalingSampleCount > 0
                ? state.cadence.maxCadenceRPM : nil,
            vehiclePassCount: nil
        )
    }

    /// Drops a HealthKit shadow sample once it's aged past `healthKitHRStalenessWindow`
    /// (#161), so `hrSource` never keeps reporting `.healthKit` for a reading no longer
    /// safe to call live. Called both continuously (`.elapsedTick`) and at the moment
    /// of promotion (`.hrPairingChanged` disconnect) so the two paths can't disagree.
    private func expireStaleHealthKitSample(in state: inout State) {
        guard let sample = state.healthKitHRSample,
              date.now.timeIntervalSince(sample.receivedAt) >= Self.healthKitHRStalenessWindow
        else { return }
        state.healthKitHRSample = nil
    }
}
