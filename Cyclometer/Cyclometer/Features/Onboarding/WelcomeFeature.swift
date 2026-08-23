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

        private static let requiredDomains: [PermissionDomain] = [.bluetooth, .locationWhenInUse, .motion]

        func state(for domain: PermissionDomain) -> PermissionState {
            permissionStates[domain] ?? .notDetermined
        }

        /// Health is excluded by simply not being in `requiredDomains` — no
        /// domain-specific branching anywhere else in the feature.
        var isNextEnabled: Bool {
            Self.requiredDomains.allSatisfy { state(for: $0).isGranted || state(for: $0) == .unavailable }
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
