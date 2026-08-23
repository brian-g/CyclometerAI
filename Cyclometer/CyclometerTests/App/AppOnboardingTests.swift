import Testing
import Foundation
import ComposableArchitecture
@testable import Cyclometer

/// The onboarding gate (#105): whether `AppFeature.State.onboarding` gets constructed
/// on launch, and at which step, given `hasCompletedOnboarding`/`hasCompletedWelcomeStep`
/// and the current permission snapshot.
@MainActor
@Suite("AppFeature — onboarding gating")
struct AppOnboardingTests {

    /// Seeded in the same dependency scope the store reads from, matching
    /// `AppPairingTests`/`StartSheetFeatureTests`.
    static func makeStore(
        hasCompletedOnboarding: Bool = false,
        hasCompletedWelcomeStep: Bool = false,
        permissionsClient: PermissionsClient = .testValue
    ) -> TestStoreOf<AppFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock {
                $0.hasCompletedOnboarding = hasCompletedOnboarding
                $0.hasCompletedWelcomeStep = hasCompletedWelcomeStep
            }
            return TestStore(initialState: AppFeature.State()) {
                AppFeature()
            } withDependencies: {
                $0.defaultFileStorage = storage
                $0.permissionsClient = permissionsClient
                $0.bleCSCClient = .testValue
                $0.variaRadarClient = .testValue
                $0.bleHRClient = .testValue
            }
        }
    }

    @Test("Fresh install presents onboarding at Welcome")
    func freshInstallPresentsWelcome() async {
        let store = Self.makeStore()

        await store.send(.task) {
            $0.onboarding = OnboardingFeature.State(step: .welcome)
        }
        await store.finish()
    }

    @Test("Relaunch mid-flow resumes at Sensor Pairing, not Welcome")
    func midFlowRelaunchResumesAtSensorPairing() async {
        let store = Self.makeStore(
            hasCompletedWelcomeStep: true,
            permissionsClient: .mock(initial: [
                .bluetooth: .granted,
                .locationWhenInUse: .granted,
                .motion: .granted,
            ])
        )

        await store.send(.task) {
            $0.onboarding = OnboardingFeature.State(step: .sensorPairing)
        }
        await store.send(.onboarding(.task))
        await store.receive(\.onboarding.requiredPermissionsChecked)
        await store.finish()
    }

    @Test("Completed rider never sees onboarding again")
    func completedRiderNeverSeesOnboardingAgain() async {
        let store = Self.makeStore(hasCompletedOnboarding: true)

        await store.send(.task)
        await store.finish()

        #expect(store.state.onboarding == nil)
    }

    @Test("Completed rider with a required permission now denied still never sees onboarding")
    func completedRiderIgnoresRevokedPermission() async {
        let store = Self.makeStore(
            hasCompletedOnboarding: true,
            permissionsClient: .mock(initial: [.bluetooth: .denied])
        )

        await store.send(.task)
        await store.finish()

        #expect(store.state.onboarding == nil)
    }

    @Test("Resuming at Sensor Pairing with a revoked required permission clamps back to Welcome")
    func revokedPermissionClampsBackToWelcome() async {
        let store = Self.makeStore(
            hasCompletedWelcomeStep: true,
            permissionsClient: .mock(initial: [.bluetooth: .denied])
        )

        await store.send(.task) {
            $0.onboarding = OnboardingFeature.State(step: .sensorPairing)
        }
        await store.send(.onboarding(.task))
        await store.receive(\.onboarding.requiredPermissionsChecked) {
            $0.onboarding?.step = .welcome
        }
        await store.finish()
    }

    @Test("Completing the flow persists and dismisses")
    func completingTheFlowPersistsAndDismisses() async {
        let store = Self.makeStore(permissionsClient: .mock(initial: [
            .bluetooth: .granted,
            .locationWhenInUse: .granted,
            .motion: .granted,
        ]))

        await store.send(.task) {
            $0.onboarding = OnboardingFeature.State(step: .welcome)
        }
        await store.send(.onboarding(.task))

        // Welcome's own `.task` populates its permission state — #106's Next button
        // is gated on it, so this subscription is required before Next can fire.
        await store.send(.onboarding(.welcome(.task)))
        await store.receive(\.onboarding.welcome.permissionChanged) { $0.onboarding?.welcome.permissionStates[.bluetooth] = .granted }
        await store.receive(\.onboarding.welcome.permissionChanged) { $0.onboarding?.welcome.permissionStates[.locationWhenInUse] = .granted }
        await store.receive(\.onboarding.welcome.permissionChanged) { $0.onboarding?.welcome.permissionStates[.motion] = .granted }
        await store.receive(\.onboarding.welcome.permissionChanged) { $0.onboarding?.welcome.permissionStates[.health] = .notDetermined }

        // `@Shared` writes become visible to TestStore's exhaustive diffing at the
        // very next call regardless of which hop performs them, so each preference
        // write is asserted at the `send` rather than the `.receive` where it
        // textually happens; plain fields (`step`, `onboarding`) assert normally, at
        // their own hop.
        await store.send(.onboarding(.welcome(.nextButtonTapped))) {
            $0.onboarding?.$preferences.withLock { $0.hasCompletedWelcomeStep = true }
        }
        await store.receive(\.onboarding.welcome.delegate.next) {
            $0.onboarding?.step = .sensorPairing
        }

        await store.send(.onboarding(.sensorPairing(.nextButtonTapped))) {
            $0.onboarding?.$preferences.withLock { $0.hasCompletedOnboarding = true }
        }
        await store.receive(\.onboarding.sensorPairing.delegate.next)
        await store.receive(\.onboarding.delegate.completed) {
            $0.onboarding = nil
        }

        #expect(store.state.preferences.hasCompletedOnboarding)
        await store.finish()
    }
}
