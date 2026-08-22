import Testing
import Foundation
import ComposableArchitecture
@testable import Cyclometer

@MainActor
@Suite("OnboardingFeature")
struct OnboardingFeatureTests {

    static func makeStore(
        step: OnboardingFeature.Step,
        permissionsClient: PermissionsClient = .testValue
    ) -> TestStoreOf<OnboardingFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            TestStore(initialState: OnboardingFeature.State(step: step)) {
                OnboardingFeature()
            } withDependencies: {
                $0.defaultFileStorage = storage
                $0.permissionsClient = permissionsClient
            }
        }
    }

    @Test("Welcome's next delegate advances the step and marks Welcome complete")
    func welcomeNextAdvancesStep() async {
        let store = Self.makeStore(step: .welcome)

        // `@Shared` writes become visible to TestStore's exhaustive diffing at the
        // very next call regardless of which hop performs them, so the preference
        // write is asserted here rather than at the `.receive` where it textually
        // happens; `step` is a plain field and asserts normally, at its own hop.
        await store.send(.welcome(.nextButtonTapped)) {
            $0.$preferences.withLock { $0.hasCompletedWelcomeStep = true }
        }
        await store.receive(\.welcome.delegate.next) {
            $0.step = .sensorPairing
        }
    }

    @Test("Sensor pairing's next delegate marks onboarding complete and bubbles up")
    func sensorPairingNextCompletesOnboarding() async {
        let store = Self.makeStore(step: .sensorPairing)

        await store.send(.sensorPairing(.nextButtonTapped)) {
            $0.$preferences.withLock { $0.hasCompletedOnboarding = true }
        }
        await store.receive(\.sensorPairing.delegate.next)
        await store.receive(\.delegate.completed)
    }

    @Test(".task on Welcome does not check permissions — that decision belongs to Welcome itself")
    func taskOnWelcomeIsANoOp() async {
        let store = Self.makeStore(
            step: .welcome,
            permissionsClient: .mock(initial: [.bluetooth: .denied])
        )

        await store.send(.task)
        await store.finish()
    }

    @Test(".task on Sensor Pairing with every required domain granted stays put")
    func taskOnSensorPairingWithGrantedPermissionsStaysPut() async {
        let store = Self.makeStore(
            step: .sensorPairing,
            permissionsClient: .mock(initial: [
                .bluetooth: .granted,
                .locationWhenInUse: .granted,
                .motion: .granted,
            ])
        )

        await store.send(.task)
        await store.receive(\.requiredPermissionsChecked)

        #expect(store.state.step == .sensorPairing)
    }

    @Test(".task on Sensor Pairing with motion unavailable (Simulator) still stays put")
    func taskOnSensorPairingWithUnavailableMotionStaysPut() async {
        let store = Self.makeStore(
            step: .sensorPairing,
            permissionsClient: .mock(initial: [
                .bluetooth: .granted,
                .locationWhenInUse: .granted,
                .motion: .unavailable,
            ])
        )

        await store.send(.task)
        await store.receive(\.requiredPermissionsChecked)

        #expect(store.state.step == .sensorPairing)
    }
}
