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

    /// The same device stretched tall enough to hold the whole list, so sections below the
    /// first screen, such as Cadence Zones (#79), are on the reference too.
    private lazy var fullHeightDevice = ViewImageConfig(
        safeArea: device.safeArea,
        size: CGSize(width: 402, height: 2_200),
        traits: device.traits
    )

    // MARK: Harness

    /// Each store gets its own in-memory file system, and the seed happens in the same
    /// scope — otherwise the seed and the store read different storage. Same idiom as
    /// `SettingsFeatureTests.makeStore` / `DeviceManagementSnapshotTests.screen`.
    private func screen(
        wheelCircumferenceMM: Int = WheelPreset.default.circumferenceMM,
        pairedSensors: [PairedSensor] = [],
        riderProfile profile: RiderProfile = RiderProfile(),
        isSystemLiveActivityEnabled: Bool = true,
        customCircumferenceDraft: String? = nil,
        restingOverrideDraft: String? = nil,
        maxOverrideDraft: String? = nil
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
            $riderProfile.withLock { $0 = profile }
            // Seeded as well as stubbed: the snapshot doesn't wait for `.task` to read it.
            var state = SettingsFeature.State()
            state.isSystemLiveActivityEnabled = isSystemLiveActivityEnabled
            state.customCircumferenceDraft = customCircumferenceDraft
            state.restingOverrideDraft = restingOverrideDraft
            state.maxOverrideDraft = maxOverrideDraft
            var liveActivityClient = LiveActivityClient.testValue
            liveActivityClient.isEnabled = { isSystemLiveActivityEnabled }
            return Store(initialState: state) {
                SettingsFeature()
            } withDependencies: {
                $0.bleCSCClient = .testValue
                $0.variaRadarClient = .testValue
                $0.bleHRClient = .testValue
                $0.healthKitClient = .testValue
                $0.liveActivityClient = liveActivityClient
                $0.date = .constant(Date(timeIntervalSince1970: 1_000_000))
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
        on config: ViewImageConfig? = nil,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        assertSnapshot(
            of: UIHostingController(rootView: view.preferredColorScheme(.light)),
            as: .image(on: config ?? device),
            named: "\(name)-light", file: file, testName: testName, line: line
        )
        assertSnapshot(
            of: UIHostingController(rootView: view.preferredColorScheme(.dark)),
            as: .image(on: config ?? device, traits: .init(userInterfaceStyle: .dark)),
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
    /// count reads something other than zero. The value is in range, so the row
    /// shows no message (#429).
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

    /// An out-of-range draft in the manual field: the range message appears under
    /// Circumference, in that row (#424), in `cyRatingBad` (#429).
    func testCustomWheelCircumferenceInvalid() {
        assertBothSchemes(
            screen(wheelCircumferenceMM: 2140, customCircumferenceDraft: "900"),
            named: "customWheelCircumferenceInvalid"
        )
    }

    /// Both HR overrides set (#162) — the two new fields show real committed
    /// numbers rather than the placeholder hint `testDefault` exercises.
    func testHRZoneOverridesSet() {
        assertBothSchemes(
            screen(riderProfile: RiderProfile(restingOverrideBPM: 52, maxOverrideBPM: 185)),
            named: "hrZoneOverridesSet"
        )
    }

    /// Both HR override drafts out of range — the inputs `SettingsFeatureTests` pins to
    /// `.restingOutOfRange` / `.maxOutOfRange` — so each row's error shows in
    /// `cyRatingBad` (#429).
    func testHRZoneOverridesInvalid() {
        assertBothSchemes(
            screen(restingOverrideDraft: "20", maxOverrideDraft: "50"),
            named: "hrZoneOverridesInvalid"
        )
    }

    /// The whole list at its defaults, down to About — the only reference that reaches the
    /// Cadence Zones section (#79): the issue's default ranges, steppers on Z1–Z4, and Reset.
    func testSettingsFullHeight() {
        assertBothSchemes(screen(), named: "fullHeight", on: fullHeightDevice)
    }

    /// Live Activities turned off for the app in iOS Settings (#313): the Show Live Activity
    /// toggle is disabled, and its row explains and links to iOS Settings.
    func testLiveActivitiesOffInIOS() {
        assertBothSchemes(screen(isSystemLiveActivityEnabled: false), named: "liveActivitiesOffInIOS")
    }
}
