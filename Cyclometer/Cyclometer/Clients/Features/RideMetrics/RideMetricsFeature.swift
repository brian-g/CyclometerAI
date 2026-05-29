import ComposableArchitecture

/// Page 1 — Primary ride dashboard.
/// Hero: speed (82 pt). Secondary grid: HR zone, cadence, distance, elapsed time.
@Reducer
struct RideMetricsFeature {

    @ObservableState
    struct State: Equatable {
        var speedKPH:       Double = 0.0
        var heartRateBPM:   Int    = 0
        var hrZone:         Int    = 0     // 1–5; computed from Karvonen at query time
        var cadenceRPM:     Int    = 0
        var distanceKM:     Double = 0.0
        var elapsedSeconds: Int    = 0
        var isRiding:       Bool   = false
        var isPaused:       Bool   = false
        // HealthKit parameters for Karvonen formula
        var maxHeartRate:     Int  = 190
        var restingHeartRate: Int  = 55
    }

    enum Action {
        case onAppear
        case onDisappear
        case speedUpdated(Double)
        case heartRateUpdated(Int)
        case cadenceUpdated(Int)
        case elapsedTick
        case startRideTapped
        case pauseRideTapped
        case resumeRideTapped
        case stopRideTapped
        case healthKitValuesLoaded(maxHR: Int, restingHR: Int)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                // TODO: start BLE subscriptions, HealthKit fetch
                return .none

            case .onDisappear:
                return .none

            case .speedUpdated(let kph):
                state.speedKPH = kph
                return .none

            case .heartRateUpdated(let bpm):
                state.heartRateBPM = bpm
                state.hrZone = HeartRateZone.zone(
                    bpm: bpm,
                    maxHR: state.maxHeartRate,
                    restingHR: state.restingHeartRate
                ).rawValue
                return .none

            case .cadenceUpdated(let rpm):
                state.cadenceRPM = rpm
                return .none

            case .elapsedTick:
                if state.isRiding && !state.isPaused {
                    state.elapsedSeconds += 1
                }
                return .none

            case .startRideTapped:
                state.isRiding = true
                state.isPaused = false
                return .none

            case .pauseRideTapped:
                state.isPaused = true
                return .none

            case .resumeRideTapped:
                state.isPaused = false
                return .none

            case .stopRideTapped:
                state.isRiding = false
                state.isPaused = false
                return .none

            case .healthKitValuesLoaded(let maxHR, let restingHR):
                state.maxHeartRate     = maxHR
                state.restingHeartRate = restingHR
                return .none
            }
        }
    }
}
