import ComposableArchitecture

/// Active ride state — owns radar, HR, speed/cadence, and recording state.
/// Radar column state is also here — fed to RideDashboardView.
@Reducer
struct ActiveRideFeature {

    @ObservableState
    struct State: Equatable {
        var isPaused: Bool = false
        var elapsedSeconds: Int = 0
        var speedKPH: Double = 0
        var heartRateBPM: Int = 0
        var hrZone: Int = 0
        var cadenceRPM: Int = 0
        var distanceKM: Double = 0
        var maxHeartRate: Int = 190
        var restingHeartRate: Int = 55
        // Radar
        var isRadarPaired: Bool = false
        var radarTargets: [RadarTarget] = []
    }

    enum Action {
        case pauseTapped
        case resumeTapped
        case finishTapped
        case speedUpdated(Double)
        case heartRateUpdated(Int)
        case cadenceUpdated(Int)
        case elapsedTick
        case radarTargetsUpdated([RadarTarget])
        case radarPairingChanged(Bool)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .pauseTapped:
                state.isPaused = true
                return .none
            case .resumeTapped:
                state.isPaused = false
                return .none
            case .finishTapped:
                return .none
            case .speedUpdated(let kph):
                state.speedKPH = kph
                return .none
            case .heartRateUpdated(let bpm):
                state.heartRateBPM = bpm
                state.hrZone = HeartRateZone.zone(
                    bpm: bpm, maxHR: state.maxHeartRate, restingHR: state.restingHeartRate
                ).rawValue
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
            case .radarPairingChanged(let paired):
                state.isRadarPaired = paired
                return .none
            }
        }
    }
}
