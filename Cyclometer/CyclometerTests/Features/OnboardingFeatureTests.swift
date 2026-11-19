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
        let store = Self.makeStore(
            step: .welcome,
            permissionsClient: .mock(initial: [
                .bluetooth: .granted,
                .locationWhenInUse: .granted,
                .motion: .granted,
            ])
        )

        // Welcome's own `.task` populates its permission state — #106's Next button
        // is gated on it, so this subscription is required before Next can fire.
        let task = await store.send(.welcome(.task))
        await store.receive(\.welcome.permissionChanged) { $0.welcome.permissionStates[.locationWhenInUse] = .granted }
        await store.receive(\.welcome.permissionChanged) { $0.welcome.permissionStates[.motion] = .granted }
        await store.receive(\.welcome.permissionChanged) { $0.welcome.permissionStates[.bluetooth] = .granted }
        await store.receive(\.welcome.permissionChanged) { $0.welcome.permissionStates[.health] = .notDetermined }

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

        await task.cancel()
    }

    @Test("Sensor pairing's next delegate marks onboarding complete and bubbles up")
    func sensorPairingNextCompletesOnboarding() async {
        let store = Self.makeStore(step: .sensorPairing)

        await store.send(.sensorPairing(.nextButtonTapped)) {
            $0.$preferences.withLock { $0.hasCompletedOnboarding = true }
        }
        await store.receive(\.sensorPairing.deviceManagement.onDisappear)
        await store.receive(\.sensorPairing.delegate.next)
        await store.receive(\.delegate.completed)
    }

    /// `AppFeature` nils `onboarding` on `.completed`, so the device list's own `.onDisappear`
    /// lands on an absent child and is dropped. S02 has to end the list's pairing scan itself
    /// before Next, or every client's count stays at 1 for the first session and #585's drop
    /// never runs.
    @Test("Next on Sensor Pairing ends the device list's pairing scan on every client")
    func sensorPairingNextEndsThePairingScan() async {
        let log = LockIsolated<[StartSheetPresentationTests.ScanCall]>([])
        let storage = FileStorage.inMemory
        let store = withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            var csc = BLECSCClient.testValue
            csc.beginPairingScan = { log.withValue { $0.append(.begin(.speedCadence)) } }
            csc.endPairingScan = { log.withValue { $0.append(.end(.speedCadence)) } }
            var radar = VariaRadarClient.testValue
            radar.beginPairingScan = { log.withValue { $0.append(.begin(.radar)) } }
            radar.endPairingScan = { log.withValue { $0.append(.end(.radar)) } }
            var hr = BLEHRClient.testValue
            hr.beginPairingScan = { log.withValue { $0.append(.begin(.heartRate)) } }
            hr.endPairingScan = { log.withValue { $0.append(.end(.heartRate)) } }
            return TestStore(initialState: OnboardingFeature.State(step: .sensorPairing)) {
                OnboardingFeature()
            } withDependencies: {
                $0.defaultFileStorage = storage
                $0.bleCSCClient = csc
                $0.variaRadarClient = radar
                $0.bleHRClient = hr
                $0.continuousClock = TestClock()
            }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.sensorPairing(.deviceManagement(.task)))
        await store.send(.sensorPairing(.nextButtonTapped))
        await store.receive(\.delegate.completed)
        await store.finish()

        #expect(log.value == [
            .begin(.speedCadence), .begin(.radar), .begin(.heartRate),
            .end(.speedCadence), .end(.radar), .end(.heartRate),
        ])
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
