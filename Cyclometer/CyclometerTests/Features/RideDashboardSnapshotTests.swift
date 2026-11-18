import XCTest
import SnapshotTesting
import SwiftUI
import ComposableArchitecture
@testable import Cyclometer

/// S05: the whole dashboard (#352), grabber, banner slot, page dots and ride controls over one
/// map-free page. The widgets have their own suites. These pin the chrome around them, and where
/// it sits against the grid.
///
/// Edit mode opens on an empty page, S08's "Empty page". Placed widgets wiggle, so each capture
/// would catch a different angle, and Reduce Motion can't be set from outside.
///
/// Skipped in CI along with the other snapshot suites (see `.github/workflows/tests.yml`).
final class RideDashboardSnapshotTests: XCTestCase {

    /// iPhone 17 Pro, full screen: the dashboard is a `fullScreenCover`.
    private let device = ViewImageConfig(
        safeArea: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0),
        size: CGSize(width: 402, height: 874),
        traits: UITraitCollection { traits in
            traits.horizontalSizeClass = .compact
            traits.verticalSizeClass = .regular
            traits.displayScale = 3
        }
    )

    /// A map-free page: a live `Map`'s tiles can't be pinned.
    private static let layout = DashboardLayout(pages: [
        DashboardPage(placements: [
            WidgetPlacement(SpeedDashboardWidget.self, size: .twoByTwo, row: 0, column: 0),
            WidgetPlacement(CadenceDashboardWidget.self, size: .twoByOne, row: 2, column: 0),
            WidgetPlacement(HeartRateDashboardWidget.self, size: .oneByOne, row: 3, column: 0),
            WidgetPlacement(HRZonesDashboardWidget.self, size: .oneByOne, row: 3, column: 1),
            WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 4, column: 0),
            WidgetPlacement(DirectionsDashboardWidget.self, size: .oneByOne, row: 4, column: 1)
        ]),
        DashboardPage(placements: [
            WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 0, column: 0)
        ])
    ])

    /// Edit mode shows an empty page, where `layout` above would have pruned it.
    private static let editLayout = DashboardLayout(pages: [DashboardPage(placements: [])] + layout.pages)

    // MARK: Harness

    private func assertDashboard(
        recordingState: RideRecordingState = .active,
        pairedSensors: [PairedSensor] = [],
        configure: (inout ActiveRideFeature.State) -> Void = { _ in },
        isEditing: Bool = false,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let storage = FileStorage.inMemory
        let store = withDependencies {
            $0.defaultFileStorage = storage
            $0.persistenceClient = .mock()
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock {
                $0.preferredUnit = .imperial
                $0.pairedSensors = pairedSensors
                $0.dashboardLayout = isEditing ? Self.editLayout : Self.layout
            }
            var state = ActiveRideFeature.State(
                recordingState: recordingState,
                elapsedSeconds: 2340,
                heartRateBPM: 155,
                hrZone: 4,
                isHRPaired: true,
                cadence: CadenceFeature.State(cadenceRPM: 87),
                distanceMeters: 12300,
                speed: SpeedFeature.State(speedMPS: 7.89, activeSpeedSource: .gps),
                maxSpeedMPS: 9.47,
                speedSampleCount: 1560
            )
            state.isEditingDashboard = isEditing
            configure(&state)
            return Store(initialState: state) {
                ActiveRideFeature()
            } withDependencies: {
                $0.defaultFileStorage = storage
                $0.persistenceClient = .mock()
            }
        }
        for scheme in [ColorScheme.light, .dark] {
            assertSnapshot(
                of: RideDashboardView(store: store)
                    .environment(\.locale, Locale(identifier: "en_US"))
                    .preferredColorScheme(scheme),
                // Glass composites against a real window; offscreen, the controls' discs aren't drawn.
                // Captured at once, the glass is still settling, and the control band differs run to run.
                as: .wait(for: 1, on: .image(drawHierarchyInKeyWindow: true, layout: .device(config: device),
                                             traits: .init(userInterfaceStyle: scheme == .dark ? .dark : .light))),
                named: scheme == .dark ? "dark" : "light",
                file: file,
                testName: testName,
                line: line
            )
        }
    }

    // Named for this screen — reference PNGs are flat in the test bundle.

    func testRideDashboardRiding() {
        assertDashboard()
    }

    /// Resume and Finish in place of Pause, and the Sensors button for a radar that isn't connected.
    func testRideDashboardPausedSensorMissing() {
        assertDashboard(
            recordingState: .paused,
            pairedSensors: [PairedSensor(peripheralID: UUID(0), role: .radar, displayName: "Varia RTL515")]
        )
    }

    func testRideDashboardBanner() {
        assertDashboard(configure: {
            $0.speed.sourceSwitchBanner = SpeedFeature.gpsFallbackBannerText(sensorName: "Wahoo RPM")
        })
    }

    /// S07: Add and Done beside the island, no grabber.
    func testRideDashboardEditMode() {
        assertDashboard(isEditing: true)
    }
}
