import ComposableArchitecture

/// Active ride state — owns radar, HR, speed/cadence, and recording state.
/// Radar column state is also here — fed to RideDashboardView.
@Reducer
struct ActiveRideFeature {

    @Dependency(\.continuousClock) var clock
    @Dependency(\.bleHRClient) var bleHRClient
    @Dependency(\.variaRadarClient) var variaRadarClient
    @Dependency(\.hapticsClient) var hapticsClient

    @ObservableState
    struct State: Equatable {
        var isPaused: Bool = false
        var elapsedSeconds: Int = 0
        var speedKPH: Double = 0
        var heartRateBPM: Int = 0
        var hrZone: Int = 0
        var isHRPaired: Bool = false
        var cadenceRPM: Int = 0
        var distanceKM: Double = 0
        var maxHeartRate: Int = 190
        var restingHeartRate: Int = 55
        // Speed statistics
        var maxSpeedKPH: Double = 0
        var speedSampleCount: Int = 0
        var speedSampleSum: Double = 0
        var averageSpeedKPH: Double {
            speedSampleCount > 0 ? speedSampleSum / Double(speedSampleCount) : 0
        }
        // Radar
        var isRadarPaired: Bool = false
        var radarTargets: [RadarTarget] = []
    }

    enum Action {
        case task
        case pauseTapped
        case resumeTapped
        case finishTapped
        case speedUpdated(Double)
        case heartRateUpdated(Int)
        case hrPairingChanged(Bool)
        case cadenceUpdated(Int)
        case elapsedTick
        case radarTargetsUpdated([RadarTarget])
        case radarConnectionChanged(VariaRadarClient.ConnectionState)
        case radarReconnectTimedOut
    }

    private enum CancelID { case radarLossTimer }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                // Timer continues while the reducer is alive. Cancelled automatically
                // when activeRide becomes nil (via AppFeature.ifLet) or when the
                // SwiftUI .task modifier is cancelled on view disappearance.
                // Note: timer pauses when dashboard is minimised in this bootstrap;
                // move to AppFeature for continuous background timing (M3).
                return .merge(
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
                    }
                )
            case .pauseTapped:
                state.isPaused = true
                return .none
            case .resumeTapped:
                state.isPaused = false
                return .none
            case .finishTapped:
                return .run { [bleHRClient, variaRadarClient] _ in
                    // Independent teardowns — run concurrently.
                    async let hr: Void = bleHRClient.disconnect()
                    async let radar: Void = variaRadarClient.disconnect()
                    _ = await (hr, radar)
                }
            case .speedUpdated(let kph):
                state.speedKPH = kph
                if kph > 0 {
                    state.speedSampleCount += 1
                    state.speedSampleSum += kph
                }
                if kph > state.maxSpeedKPH { state.maxSpeedKPH = kph }
                return .none
            case .heartRateUpdated(let bpm):
                state.heartRateBPM = bpm
                state.hrZone = HeartRateZone.zone(
                    bpm: bpm, maxHR: state.maxHeartRate, restingHR: state.restingHeartRate
                ).rawValue
                return .none
            case .hrPairingChanged(let paired):
                state.isHRPaired = paired
                if !paired {
                    state.heartRateBPM = 0
                    state.hrZone = 0
                }
                return .none
            case .cadenceUpdated(let rpm):
                state.cadenceRPM = rpm
                return .none
            case .elapsedTick:
                if !state.isPaused { state.elapsedSeconds += 1 }
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
            }
        }
    }
}
