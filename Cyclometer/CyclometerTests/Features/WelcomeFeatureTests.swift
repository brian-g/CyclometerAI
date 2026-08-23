import Testing
import Foundation
import UIKit
import ComposableArchitecture
@testable import Cyclometer

@MainActor
@Suite("WelcomeFeature")
struct WelcomeFeatureTests {

    static func makeStore(permissionsClient: PermissionsClient) -> TestStoreOf<WelcomeFeature> {
        TestStore(initialState: WelcomeFeature.State()) {
            WelcomeFeature()
        } withDependencies: {
            $0.permissionsClient = permissionsClient
        }
    }

    @Test(".task replays every domain's seeded status, in PermissionDomain.allCases order")
    func taskReplaysInitialStatuses() async {
        let store = Self.makeStore(permissionsClient: .mock(initial: [
            .bluetooth: .granted,
            .locationWhenInUse: .denied,
            .motion: .unavailable,
            .health: .notDetermined,
        ]))

        let task = await store.send(.task)
        await store.receive(\.permissionChanged) { $0.permissionStates[.bluetooth] = .granted }
        await store.receive(\.permissionChanged) { $0.permissionStates[.locationWhenInUse] = .denied }
        await store.receive(\.permissionChanged) { $0.permissionStates[.motion] = .unavailable }
        await store.receive(\.permissionChanged) { $0.permissionStates[.health] = .notDetermined }
        await task.cancel()
    }

    // Pure — no TestStore needed, isNextEnabled is a computed property on State.
    @Test("Next requires Bluetooth, Location, Motion each granted or unavailable; Health never gates",
          arguments: [
        // (bluetooth, location, motion, health, expected)
        (PermissionState.granted, PermissionState.granted, PermissionState.granted, PermissionState.notDetermined, true),
        (.granted, .granted, .unavailable, .notDetermined, true),               // Simulator case
        (.granted, .grantedAlways, .granted, .notDetermined, true),
        (.denied, .granted, .granted, .granted, false),
        (.granted, .restricted, .granted, .granted, false),
        (.granted, .granted, .notDetermined, .granted, false),
        (.granted, .granted, .granted, .denied, true),                          // impossible in practice, still must not gate
    ])
    func nextGating(bluetooth: PermissionState, location: PermissionState, motion: PermissionState, health: PermissionState, expected: Bool) {
        let state = WelcomeFeature.State(permissionStates: [
            .bluetooth: bluetooth, .locationWhenInUse: location, .motion: motion, .health: health,
        ])
        #expect(state.isNextEnabled == expected)
    }

    @Test("nextButtonTapped is a no-op while Next is not enabled")
    func nextButtonTappedGuardsWhenDisabled() async {
        let store = Self.makeStore(permissionsClient: .mock())
        await store.send(.nextButtonTapped)
    }

    @Test("nextButtonTapped sends delegate.next once enabled")
    func nextButtonTappedSendsDelegate() async {
        let store = Self.makeStore(permissionsClient: .mock(initial: [
            .bluetooth: .granted, .locationWhenInUse: .granted, .motion: .granted,
        ]))
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.task)
        await store.send(.nextButtonTapped)
        await store.receive(\.delegate.next)
    }

    @Test("Tapping a not-determined row requests it and the resulting change flows back through the live subscription")
    func rowTappedNotDeterminedRequests() async {
        let opened = LockIsolated<[URL]>([])
        let store = Self.makeStore(permissionsClient: .mock(onRequest: { _ in .granted }))
        store.exhaustivity = .off(showSkippedAssertions: false)
        store.dependencies.openURL = OpenURLEffect { url in opened.withValue { $0.append(url) }; return true }

        let task = await store.send(.task)
        await store.send(.rowTapped(.bluetooth))
        await store.receive(\.permissionChanged) { $0.permissionStates[.bluetooth] = .granted }

        #expect(opened.value.isEmpty)
        await task.cancel()
    }

    @Test("Tapping a denied row opens Settings and never prompts")
    func rowTappedDeniedOpensSettings() async {
        let opened = LockIsolated<[URL]>([])
        let store = Self.makeStore(permissionsClient: .mock(initial: [.bluetooth: .denied]))
        store.dependencies.openURL = OpenURLEffect { url in opened.withValue { $0.append(url) }; return true }

        let task = await store.send(.task)
        await store.receive(\.permissionChanged) { $0.permissionStates[.bluetooth] = .denied }
        await store.receive(\.permissionChanged) { $0.permissionStates[.locationWhenInUse] = .notDetermined }
        await store.receive(\.permissionChanged) { $0.permissionStates[.motion] = .notDetermined }
        await store.receive(\.permissionChanged) { $0.permissionStates[.health] = .notDetermined }

        await store.send(.rowTapped(.bluetooth)) // no permissionChanged follows — request no-ops
        #expect(opened.value == [URL(string: UIApplication.openSettingsURLString)!])

        await task.cancel()
    }

    @Test("Tapping a restricted row routes to Settings the same as denied")
    func rowTappedRestrictedOpensSettings() async {
        let opened = LockIsolated<[URL]>([])
        let store = Self.makeStore(permissionsClient: .mock(initial: [.motion: .restricted]))
        store.exhaustivity = .off(showSkippedAssertions: false)
        store.dependencies.openURL = OpenURLEffect { url in opened.withValue { $0.append(url) }; return true }

        let task = await store.send(.task)
        await store.send(.rowTapped(.motion))
        #expect(opened.value == [URL(string: UIApplication.openSettingsURLString)!])
        await task.cancel()
    }
}
