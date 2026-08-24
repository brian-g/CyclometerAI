import XCTest
import SnapshotTesting
import SwiftUI
import ComposableArchitecture
@testable import Cyclometer

/// S01 — Welcome and permissions, at the width `Design.sketch` draws the frame at.
///
/// What these pin is the *layout*: headline, supporting copy, the four permission
/// rows and their oval states, the conditional guidance text, and the Next button's
/// enabled/disabled styling. The gating behaviour behind them belongs to
/// `WelcomeFeatureTests`.
///
/// Skipped in CI along with the other snapshot suites — the references were recorded
/// against a local simulator (see `.github/workflows/tests.yml`).
final class WelcomeSnapshotTests: XCTestCase {

    /// Same device config as `DeviceManagementSnapshotTests` — the iPhone 17 Pro
    /// `Design.sketch` draws every screen at, 402x874pt.
    private let device = ViewImageConfig(
        safeArea: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0),
        size: CGSize(width: 402, height: 874),
        traits: UITraitCollection(traitsFrom: [
            UITraitCollection(horizontalSizeClass: .compact),
            UITraitCollection(verticalSizeClass: .regular),
            UITraitCollection(displayScale: 3)
        ])
    )

    // MARK: Harness

    /// State is seeded directly rather than left to `.task`'s live
    /// `permissionsClient.statuses()` subscription — the same bypass
    /// `DeviceManagementSnapshotTests` uses for `sources`, and for the same reason:
    /// an async subscription racing the snapshot capture is exactly the class of bug
    /// that produced a blank reference before (see `lessons.md`). The mock's
    /// `initial` values match what's seeded, so the view's own `.task` is a no-op
    /// against the pre-seeded state rather than a source of flakiness.
    ///
    /// Wrapped in the same `cyBgPrimary` full-bleed background `OnboardingView`
    /// renders behind every step, since that background is part of what this suite
    /// pins — same idiom as `SensorPairingSnapshotTests`.
    private func screen(permissionStates: [PermissionDomain: PermissionState]) -> some View {
        let store = Store(initialState: WelcomeFeature.State(permissionStates: permissionStates)) {
            WelcomeFeature()
        } withDependencies: {
            $0.permissionsClient = .mock(initial: permissionStates)
        }
        return ZStack {
            Color.cyBgPrimary.ignoresSafeArea()
            WelcomeView(store: store)
        }
        // Explicit rather than ambient: a reference recorded against whatever the host
        // bundle resolved would silently encode that instead of the token.
        .tint(Color.cyPrimary)
    }

    /// `testName` defaults to the *caller's* `#function` — Swift evaluates a magic
    /// literal default at the call site — so references are filed under the test that
    /// asked for them rather than under this helper.
    private func assertBothSchemes(
        _ view: some View,
        named name: String,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        assertSnapshot(
            of: UIHostingController(rootView: view.preferredColorScheme(.light)),
            as: .image(on: device),
            named: "\(name)-light", file: file, testName: testName, line: line
        )
        assertSnapshot(
            of: UIHostingController(rootView: view.preferredColorScheme(.dark)),
            as: .image(on: device, traits: .init(userInterfaceStyle: .dark)),
            named: "\(name)-dark", file: file, testName: testName, line: line
        )
    }

    // MARK: Tests

    /// Only Bluetooth answered — the state a rider is in partway through S01. Next is
    /// disabled and the guidance text is visible, mirroring `WelcomeView`'s "needs
    /// permissions" preview.
    func testNeedsPermissions() {
        assertBothSchemes(
            screen(permissionStates: [.bluetooth: .granted]),
            named: "needsPermissions"
        )
    }

    /// All four domains granted, including the optional HealthKit row — Next enabled,
    /// no guidance text, mirroring `WelcomeView`'s "all granted" preview.
    func testAllGranted() {
        assertBothSchemes(
            screen(permissionStates: [
                .bluetooth: .granted,
                .locationWhenInUse: .granted,
                .motion: .granted,
                .health: .granted
            ]),
            named: "allGranted"
        )
    }

    /// Bluetooth denied — neither existing `#Preview` exercises
    /// `PermissionStatusOval`'s red-X branch, which only `.denied`/`.restricted`
    /// render. Next stays disabled and the guidance text stays visible.
    func testDeniedBlocksNext() {
        assertBothSchemes(
            screen(permissionStates: [
                .bluetooth: .denied,
                .locationWhenInUse: .granted,
                .motion: .granted
            ]),
            named: "deniedBlocksNext"
        )
    }
}
