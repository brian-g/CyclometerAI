import ComposableArchitecture

/// Page 3 — Full-screen radar visualisation.
/// Entire page (and tab indicator dot) hidden when no Varia device is paired.
/// Target hardware: Garmin Varia RTL515 / RCT715 via raw CoreBluetooth BLE.
@Reducer
struct RadarDetailFeature {

    @ObservableState
    struct State: Equatable {
        var isRadarPaired: Bool = false
        var targets: [RadarTarget] = []
        var signalStrength: Int = 0   // RSSI dBm
    }

    enum Action {
        case onAppear
        case radarTargetsUpdated([RadarTarget])
        case pairingStatusChanged(Bool)
        case signalStrengthUpdated(Int)
        case pairNewDeviceTapped
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .none
            case .radarTargetsUpdated(let targets):
                state.targets = targets
                return .none
            case .pairingStatusChanged(let paired):
                state.isRadarPaired = paired
                return .none
            case .signalStrengthUpdated(let rssi):
                state.signalStrength = rssi
                return .none
            case .pairNewDeviceTapped:
                // TODO: Launch BLE pairing flow
                return .none
            }
        }
    }
}
