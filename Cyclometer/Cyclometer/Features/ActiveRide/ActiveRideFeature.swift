import ComposableArchitecture
import CoreLocation

/// Active ride state — owns radar, HR, speed/cadence, and recording state.
/// Radar column state is also here — fed to RideDashboardView.
@Reducer
struct ActiveRideFeature {

    @Dependency(\.continuousClock) var clock
    @Dependency(\.bleHRClient) var bleHRClient
    @Dependency(\.variaRadarClient) var variaRadarClient
    @Dependency(\.hapticsClient) var hapticsClient
    @Dependency(\.locationClient) var locationClient

    @ObservableState
    struct State: Equatable {
        var isPaused: Bool = false
        var elapsedSeconds: Int = 0
        var speedKPH: Double = 0
        var heartRateBPM: Int = 0
        var hrZone: Int = 0
        var isHRPaired: Bool = false
        var cadence = CadenceFeature.State()
        var distanceMeters: Double = 0
        var distanceKM: Double { distanceMeters / 1000.0 }
        var maxHeartRate: Int = 190
        var restingHeartRate: Int = 55
        var speed = SpeedFeature.State()
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
        // Location (GPS)
        var coordinate: Coordinate? = nil
        var altitude: Double = 0
        var heading: Double = -1
        var horizontalAccuracy: Double = 0
        var isLocationAvailable: Bool = false
    }

    enum Action: Equatable {
        case task
        case pauseTapped
        case resumeTapped
        case finishTapped
        case heartRateUpdated(Int)
        case hrPairingChanged(Bool)
        case cadence(CadenceFeature.Action)
        case elapsedTick
        case radarTargetsUpdated([RadarTarget])
        case radarConnectionChanged(VariaRadarClient.ConnectionState)
        case radarReconnectTimedOut
        case speed(SpeedFeature.Action)
        case locationUpdated(LocationUpdate)
        case locationAuthorizationResult(CLAuthorizationStatus)
    }

    private enum CancelID { case radarLossTimer }

    var body: some ReducerOf<Self> {
        Scope(state: \.speed, action: \.speed) {
            SpeedFeature()
        }
        Scope(state: \.cadence, action: \.cadence) {
            CadenceFeature()
        }
        Reduce { state, action in
            switch action {
            case .task:
                // Timer continues while the reducer is alive. Cancelled automatically
                // when activeRide becomes nil (via AppFeature.ifLet) or when the
                // SwiftUI .task modifier is cancelled on view disappearance.
                // Note: timer pauses when dashboard is minimised in this bootstrap;
                // move to AppFeature for continuous background timing (M3).
                return .merge(
                    .send(.speed(.startListening)),
                    .send(.cadence(.startListening)),
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
                    .run { [locationClient] send in
                        let status = await locationClient.requestAuthorization()
                        await send(.locationAuthorizationResult(status))
                        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
                        for await update in locationClient.startUpdates() {
                            await send(.locationUpdated(update))
                        }
                        await locationClient.stopUpdates()
                    }
                )
            case .pauseTapped:
                state.isPaused = true
                return .none
            case .resumeTapped:
                state.isPaused = false
                return .none
            case .finishTapped:
                return .run { [bleHRClient, variaRadarClient, locationClient] _ in
                    async let hr: Void = bleHRClient.disconnect()
                    async let radar: Void = variaRadarClient.disconnect()
                    async let loc: Void = locationClient.stopUpdates()
                    _ = await (hr, radar, loc)
                }
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
            case .cadence:
                return .none
            case .elapsedTick:
                if !state.isPaused {
                    state.elapsedSeconds += 1
                    state.distanceMeters += max(state.speed.speedMPS ?? 0, 0)
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
                return .send(.speed(.gpsSpeedReceived(update.speed)))
            case .locationAuthorizationResult(let status):
                state.isLocationAvailable = (status == .authorizedWhenInUse || status == .authorizedAlways)
                return .none
            case .speed:
                return .none
            }
        }
    }
}
