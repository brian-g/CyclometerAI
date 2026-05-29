import ComposableArchitecture

@Reducer
struct SettingsFeature {
    @ObservableState
    struct State: Equatable {
        var selectedUnits: String = "Imperial"
        var selectedWheelSize: String = "700 x 28c"
        var isAutoPauseEnabled: Bool = true
        var isAutoDimEnabled: Bool = true
        var shouldSetDoNotDisturb: Bool = false
        var heartRateZones: [HeartRateZoneSetting] = HeartRateZoneSetting.standardZones
        var isShowingAddAccountOptions: Bool = false
    }
    enum Action {
        case unitSelected(String)
        case wheelSizeSelected(String)
        case autoPauseToggled
        case autoDimToggled
        case doNotDisturbToggled
        case hrZoneUpperBoundAdjusted(id: Int, delta: Int)
        case addAccountTapped
        case addAccountDismissed
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .unitSelected(let unit):
                state.selectedUnits = unit; return .none
            case .wheelSizeSelected(let size):
                state.selectedWheelSize = size; return .none
            case .autoPauseToggled:
                state.isAutoPauseEnabled.toggle(); return .none
            case .autoDimToggled:
                state.isAutoDimEnabled.toggle(); return .none
            case .doNotDisturbToggled:
                state.shouldSetDoNotDisturb.toggle(); return .none
            case .hrZoneUpperBoundAdjusted(let id, let delta):
                guard let index = state.heartRateZones.firstIndex(where: { $0.id == id }) else { return .none }
                let zone = state.heartRateZones[index]
                state.heartRateZones[index].upperBound = max(zone.lowerBound, zone.upperBound + delta)
                // Normalize downstream zones
                for i in (index + 1)..<state.heartRateZones.count {
                    let lb = state.heartRateZones[i - 1].upperBound + 1
                    state.heartRateZones[i].lowerBound = lb
                    state.heartRateZones[i].upperBound = max(state.heartRateZones[i].upperBound, lb)
                }
                return .none
            case .addAccountTapped:
                state.isShowingAddAccountOptions = true; return .none
            case .addAccountDismissed:
                state.isShowingAddAccountOptions = false; return .none
            }
        }
    }
}
