import XCTest
import SnapshotTesting
import SwiftUI
import ComposableArchitecture
@testable import Cyclometer

/// S11 — Manage Sensors, at the width `Design.sketch` draws the frame at.
///
/// What these pin is the *layout*: one flat grouped list, the helper text above it, a
/// per-kind icon on each row, and the trailing text button reading Pair or Unpair.
/// The behaviour behind them belongs to `DeviceManagementFeatureTests`.
///
/// Skipped in CI along with the other snapshot suites — the references were recorded
/// against a local simulator (see `.github/workflows/tests.yml`).
final class DeviceManagementSnapshotTests: XCTestCase {

    /// The iPhone 17 Pro, which is what `Design.sketch` draws S11 at — 402x874pt, with
    /// the Dynamic Island's 62pt top inset and the home indicator's 34pt.
    ///
    /// A device config rather than a bare `.fixed` canvas: a `NavigationStack` takes its
    /// large title's leading margin from the window's layout margins, and with no window
    /// the title renders flush to x=0. The reference would then be pinning a layout the
    /// app never shows.
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
    private static let looseID = UUID(uuidString: "00000000-0000-0000-0000-00000000C5C2")!

    /// Two paired rows and two discovered ones, mixing all three kinds — the flat list's
    /// whole point, and the case the Sketch frame draws.
    private static let mixedSources: [SensorKind: [DiscoveredDevice]] = [
        .radar: [
            .init(id: radarID, name: "Varia RTL515", kinds: [.radar], roles: [.radar],
                  connectionState: .active, batteryPercent: 84)
        ],
        .speedCadence: [
            .init(id: comboID, name: "Wahoo RPM", kinds: [.speedCadence],
                  roles: [.speed, .cadence], connectionState: .active, batteryPercent: 12,
                  capabilities: .init(supportsWheelRevolutions: true,
                                      supportsCrankRevolutions: true)),
            .init(id: looseID, name: "GSC-10", kinds: [.speedCadence])
        ],
        .heartRate: [
            .init(id: strapID, name: "Polar H10", kinds: [.heartRate])
        ]
    ]

    private static let mixedRecords: [PairedSensor] = [
        PairedSensor(peripheralID: radarID, role: .radar, displayName: "Varia RTL515"),
        PairedSensor(peripheralID: comboID, role: .speed, displayName: "Wahoo RPM"),
        PairedSensor(peripheralID: comboID, role: .cadence, displayName: "Wahoo RPM")
    ]

    /// Paired but advertising on no stream — the row is synthesised from the record, and
    /// has to stay unpairable while it reads Disconnected (UX.md §S11).
    private static let outOfRangeRecords: [PairedSensor] = [
        PairedSensor(peripheralID: radarID, role: .radar, displayName: "Varia RTL515")
    ]

    // MARK: Harness

    /// Each store gets its own in-memory file system, and the seed happens in the same
    /// scope — otherwise the seed and the store read different storage. Same idiom as
    /// `DeviceManagementFeatureTests.makeStore`.
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
            return Store(initialState: DeviceManagementFeature.State(sources: sources)) {
                DeviceManagementFeature()
            } withDependencies: {
                // Every testValue stream finishes without yielding, so the seeded
                // `sources` survive `.task` rather than being replayed away.
                $0.bleCSCClient = .testValue
                $0.variaRadarClient = .testValue
                $0.bleHRClient = .testValue
                $0.continuousClock = TestClock()
                $0.defaultFileStorage = storage
            }
        }
        return NavigationStack {
            DeviceManagementView(store: store)
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

    func testMixedList() {
        assertBothSchemes(
            screen(sources: Self.mixedSources, pairedSensors: Self.mixedRecords),
            named: "mixed"
        )
    }

    /// Nothing found yet. The scanning row is the whole content, and the footer carries
    /// the only hint the rider gets — there is no state in which the scan has finished.
    func testEmptyAndScanning() {
        assertBothSchemes(screen(), named: "empty")
    }

    func testPairedButOutOfRange() {
        assertBothSchemes(
            screen(pairedSensors: Self.outOfRangeRecords),
            named: "outOfRange"
        )
    }
}
