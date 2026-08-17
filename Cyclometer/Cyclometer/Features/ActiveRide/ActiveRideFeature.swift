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

    @Dependency(\.continuousClock) var clock
    @Dependency(\.bleHRClient) var bleHRClient
    @Dependency(\.variaRadarClient) var variaRadarClient
    @Dependency(\.hapticsClient) var hapticsClient
    @Dependency(\.locationClient) var locationClient
    @Dependency(\.permissionsClient) var permissionsClient

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
        var coordinate: Coordinate? = nil
        var trackCoordinates: [Coordinate] = []
        var altitude: Double = 0
        var heading: Double = -1
        var horizontalAccuracy: Double = 0
        var isLocationAvailable: Bool = false
        var zeroSpeedSeconds: Int = 0
        var isAutoEndEnabled: Bool = true
        /// Wheel auto-calibration stands down while the rider has something more
        /// urgent to attend to, and whenever the ride isn't actively recording — a
        /// paused ride still receives GPS fixes, and stationary scatter would poison
        /// the window (PRD §8.9).
        var isCalibrationSuspended: Bool {
            recordingState != .active || radarTargets.contains { $0.threatLevel != .allClear }
        }
        // Defaults to the device locale's measurement system. This is a *read*
        // preference, so in TCA it ideally lives as shared state (`@Shared`) or
        // behind a settings dependency rather than per-feature State — that move
        // lands with UserProfile/Settings persistence. Kept here (seeded from
        // locale) until then so the imperial path is reachable today.
        var unitSystem: UnitSystem = .system
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

    private enum CancelID { case radarLossTimer }

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
                if state.isAutoEndEnabled, state.zeroSpeedSeconds >= Self.autoEndZeroSpeedSeconds {
                    return .send(.autoEndTriggered)
                }
                return .none
            case .radarTargetsUpdated(let targets):
                state.radarTargets = targets
                return .none
            case .radarConnectionChanged(let connectionState):
                switch connectionState {
                case .active:
                    state.isRadarPaired = true
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
                    return .cancel(id: CancelID.radarLossTimer)
                default:
                    return .none
                }
            case .radarReconnectTimedOut:
                state.isRadarPaired = false
                state.radarTargets = []
                return .run { [hapticsClient] _ in
                    await hapticsClient.playAdvisory()   // L1 advisory, fires once
                }
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
}
