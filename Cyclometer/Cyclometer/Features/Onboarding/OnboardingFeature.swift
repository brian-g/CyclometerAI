import ComposableArchitecture

/// Onboarding container — composes S01 (Welcome) then S02 (Sensor Pairing), presented by
/// `AppFeature` until the rider completes it (#105).
///
/// `WelcomeFeature` and `SensorPairingFeature` are scaffolds here: their real content
/// (permission rows and gating, the sensor list) lands with #106 and #107 respectively,
/// in the same files. This feature only owns sequencing and completion persistence.
@Reducer
struct OnboardingFeature {

    enum Step: Equatable {
        case welcome
        case sensorPairing
    }

    @ObservableState
    struct State: Equatable {
        /// Write access: this feature owns both onboarding-related preference fields.
        @Shared(.appPreferences) var preferences
        var step: Step
        var welcome = WelcomeFeature.State()
        var sensorPairing = SensorPairingFeature.State()
    }

    enum Action {
        case task
        case requiredPermissionsChecked(satisfied: Bool)
        case welcome(WelcomeFeature.Action)
        case sensorPairing(SensorPairingFeature.Action)
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case completed
        }
    }

    @Dependency(\.permissionsClient) var permissionsClient

    var body: some ReducerOf<Self> {
        Scope(state: \.welcome, action: \.welcome) { WelcomeFeature() }
        Scope(state: \.sensorPairing, action: \.sensorPairing) { SensorPairingFeature() }

        Reduce { state, action in
            switch action {
            case .task:
                // Only relevant when resuming past Welcome: a rider who already passed
                // it may have revoked a required permission in Settings since — the
                // Welcome-completion decision itself belongs to WelcomeFeature/#106, not
                // here, so this is a coarse defensive re-check rather than a duplicate of
                // that predicate.
                guard state.step == .sensorPairing else { return .none }
                return .run { send in
                    async let bluetooth = permissionsClient.status(.bluetooth)
                    async let location = permissionsClient.status(.locationWhenInUse)
                    async let motion = permissionsClient.status(.motion)
                    let (b, l, m) = await (bluetooth, location, motion)
                    let satisfied = b.isGranted && l.isGranted && (m.isGranted || m == .unavailable)
                    await send(.requiredPermissionsChecked(satisfied: satisfied))
                }

            case .requiredPermissionsChecked(let satisfied):
                if !satisfied { state.step = .welcome }
                return .none

            case .welcome(.delegate(.next)):
                state.step = .sensorPairing
                state.$preferences.withLock { $0.hasCompletedWelcomeStep = true }
                return .none

            case .sensorPairing(.delegate(.next)):
                state.$preferences.withLock { $0.hasCompletedOnboarding = true }
                return .send(.delegate(.completed))

            case .welcome, .sensorPairing, .delegate:
                return .none
            }
        }
    }
}
