import ComposableArchitecture
import UIKit

/// S01 — Welcome and permissions.
@Reducer
struct WelcomeFeature {

    @ObservableState
    struct State: Equatable {
        /// One entry per domain, from `permissionsClient.statuses()`'s replay + live
        /// transitions. Missing domains read as `.notDetermined`, which is also the
        /// correct "haven't asked yet" rendering — no separate loading state needed.
        var permissionStates: [PermissionDomain: PermissionState] = [:]

        /// What Next waits for. Only Location: the route is the one thing a ride can't do
        /// without. Bluetooth, Motion and Health are optional (#596, #597): without sensors,
        /// speed and distance come from GPS; without Motion, elevation does (#387); without
        /// Health, zones use defaults.
        ///
        /// `OnboardingFeature`'s resume re-check reads this too, so the gate and the
        /// Required/Optional labels can't drift apart.
        static let requiredDomains: [PermissionDomain] = [.locationWhenInUse]

        static func isRequired(_ domain: PermissionDomain) -> Bool {
            requiredDomains.contains(domain)
        }

        /// A required domain is met when granted, or when the hardware doesn't exist —
        /// `.unavailable` is not a refusal (UX.md §S01).
        static func isSatisfied(_ state: PermissionState) -> Bool {
            state.isGranted || state == .unavailable
        }

        func state(for domain: PermissionDomain) -> PermissionState {
            permissionStates[domain] ?? .notDetermined
        }

        var isNextEnabled: Bool {
            Self.requiredDomains.allSatisfy { Self.isSatisfied(state(for: $0)) }
        }
    }

    enum Action: Equatable {
        case task
        case permissionChanged(PermissionChange)
        case rowTapped(PermissionDomain)
        case nextButtonTapped
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case next
        }
    }

    @Dependency(\.permissionsClient) var permissionsClient
    @Dependency(\.openURL) var openURL

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                return .run { send in
                    for await change in permissionsClient.statuses() {
                        await send(.permissionChanged(change))
                    }
                }

            case let .permissionChanged(change):
                state.permissionStates[change.domain] = change.state
                return .none

            case let .rowTapped(domain):
                let current = state.state(for: domain)
                if current == .denied || current == .restricted {
                    return .run { _ in
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        _ = await openURL(url)
                    }
                }
                return .run { _ in _ = await permissionsClient.request(domain) }

            case .nextButtonTapped:
                guard state.isNextEnabled else { return .none }
                return .send(.delegate(.next))

            case .delegate:
                return .none
            }
        }
    }
}
