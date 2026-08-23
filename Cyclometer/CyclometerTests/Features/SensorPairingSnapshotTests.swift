import XCTest
import SnapshotTesting
import SwiftUI
import ComposableArchitecture
@testable import Cyclometer

/// S02 — Add Sensors, at the width `Design.sketch` draws the frame at.
///
/// What these pin is the *layout*: title and helper text above S11's unmodified device
/// list, and a primary Next button below it, over the onboarding background — not the
/// pairing behaviour behind the list, which belongs to `DeviceManagementFeatureTests`,
/// or S11's own layout, pinned separately by `DeviceManagementSnapshotTests`.
///
/// Skipped in CI along with the other snapshot suites — the references were recorded
/// against a local simulator (see `.github/workflows/tests.yml`).
final class SensorPairingSnapshotTests: XCTestCase {

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

    // MARK: Fixtures

    private static let radarID = UUID(uuidString: "00000000-0000-0000-0000-00000000DA01")!
    private static let comboID = UUID(uuidString: "00000000-0000-0000-0000-00000000C5C1")!
    private static let strapID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!

    /// One paired row and two discovered ones — enough to show the list is not cut off
    /// by the title/helper text above it or the Next button below.
    private static let mixedSources: [SensorKind: [DiscoveredDevice]] = [
        .radar: [
            .init(id: radarID, name: "Varia RTL515", kinds: [.radar], roles: [.radar],
                  connectionState: .active, batteryPercent: 84)
        ],
        .speedCadence: [
            .init(id: comboID, name: "Wahoo RPM", kinds: [.speedCadence])
        ],
        .heartRate: [
            .init(id: strapID, name: "Polar H10", kinds: [.heartRate])
        ]
    ]

    private static let mixedRecords: [PairedSensor] = [
        PairedSensor(peripheralID: radarID, role: .radar, displayName: "Varia RTL515")
    ]

    // MARK: Harness

    /// Same idiom as `DeviceManagementSnapshotTests.screen` — an in-memory file system
    /// seeded in the same scope the store reads it from — wrapped in the same
    /// `cyBgPrimary` full-bleed background `OnboardingView` renders behind every step,
    /// since that background is part of what this suite is pinning.
    private func screen(
        sources: [SensorKind: [DiscoveredDevice]] = [:],
        pairedSensors: [PairedSensor] = []
    ) -> some View {
        let storage = FileStorage.inMemory
        let store = withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.pairedSensors = pairedSensors }
            return Store(
                initialState: SensorPairingFeature.State(
                    deviceManagement: DeviceManagementFeature.State(sources: sources)
                )
            ) {
                SensorPairingFeature()
            } withDependencies: {
                $0.bleCSCClient = .testValue
                $0.variaRadarClient = .testValue
                $0.bleHRClient = .testValue
                $0.continuousClock = TestClock()
                $0.defaultFileStorage = storage
            }
        }
        return ZStack {
            Color.cyBgPrimary.ignoresSafeArea()
            SensorPairingView(store: store)
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

    /// Nothing paired or discovered yet — the state a rider actually lands in the first
    /// time they see this screen, and the case UX.md §S02 calls out ("every row in its
    /// unpaired state").
    ///
    /// Named distinctly from `DeviceManagementSnapshotTests.testEmptyAndScanning`: the
    /// project's `PBXFileSystemSynchronizedRootGroup` flattens every `__Snapshots__`
    /// subfolder into one bundle directory at build time, so two suites' methods
    /// sharing a name collide on the same `<method>.<named>-<scheme>.png` regardless of
    /// which per-class folder they live in on disk.
    func testAddSensorsEmptyAndScanning() {
        assertBothSchemes(screen(), named: "empty")
    }

    func testAddSensorsWithSensorsDiscoveredAndOnePaired() {
        assertBothSchemes(
            screen(sources: Self.mixedSources, pairedSensors: Self.mixedRecords),
            named: "mixed"
        )
    }
}
