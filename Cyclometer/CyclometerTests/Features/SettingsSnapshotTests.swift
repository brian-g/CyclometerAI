import XCTest
import SnapshotTesting
import SwiftUI
import ComposableArchitecture
@testable import Cyclometer

/// S12 — Settings, at the width `Design.sketch` draws the frame at.
///
/// What these pin is the *layout*: the General section (units, wheel size, auto-pause,
/// auto-dim, sensor count) and as much of the HR Zones section as fits the frame —
/// both closed as separate issues (#102, #103) but rendered by one `SettingsView`, so
/// one screen capture per state is the right unit, not one per section. The behaviour
/// behind them belongs to `SettingsFeatureTests`.
///
/// Skipped in CI along with the other snapshot suites — the references were recorded
/// against a local simulator (see `.github/workflows/tests.yml`).
final class SettingsSnapshotTests: XCTestCase {

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

    /// Each store gets its own in-memory file system, and the seed happens in the same
    /// scope — otherwise the seed and the store read different storage. Same idiom as
    /// `SettingsFeatureTests.makeStore` / `DeviceManagementSnapshotTests.screen`.
    private func screen(
        wheelCircumferenceMM: Int = WheelPreset.default.circumferenceMM,
        pairedSensors: [PairedSensor] = []
    ) -> some View {
        let storage = FileStorage.inMemory
        let store = withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock {
                // Pinned rather than left at `.system`: the fallback reads
                // `Locale.current`, and a reference recorded on a machine with a
                // different locale would silently differ (#108's "no test depends
                // on the host machine's locale" criterion, applied to a pixel
                // reference rather than an assertion).
                $0.preferredUnit = .imperial
                $0.wheelCircumferenceMM = wheelCircumferenceMM
                $0.pairedSensors = pairedSensors
            }
            @Shared(.riderProfile) var riderProfile
            return Store(initialState: SettingsFeature.State()) {
                SettingsFeature()
            } withDependencies: {
                $0.bleCSCClient = .testValue
                $0.variaRadarClient = .testValue
                $0.bleHRClient = .testValue
                $0.continuousClock = TestClock()
                $0.defaultFileStorage = storage
            }
        }
        return NavigationStack {
            SettingsView(store: store)
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

    /// Default preferences and rider profile — a preset wheel size, nothing paired,
    /// zone boundaries at their Karvonen defaults.
    func testDefault() {
        assertBothSchemes(screen(), named: "default")
    }

    /// A non-preset circumference, which is the only thing that reveals the manual
    /// entry field, plus a couple of paired sensors so the Sensors row's trailing
    /// count reads something other than zero.
    func testCustomWheelCircumference() {
        assertBothSchemes(
            screen(
                wheelCircumferenceMM: 2140,
                pairedSensors: [
                    PairedSensor(peripheralID: UUID(), role: .speed, displayName: "Wahoo RPM"),
                    PairedSensor(peripheralID: UUID(), role: .radar, displayName: "Varia RTL515")
                ]
            ),
            named: "customWheelCircumference"
        )
    }
}
