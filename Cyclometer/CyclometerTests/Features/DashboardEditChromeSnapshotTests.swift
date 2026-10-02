import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

/// S07 edit mode's per-widget chrome (#141): the card with its hairline border, and the remove
/// button centred on the card's corner. Two 1×1 widgets side by side over a 2×1, so the gap between
/// neighbouring cards and the two scales are pinned too.
///
/// The wiggle is a separate modifier and isn't applied here: each capture would catch a different
/// angle.
final class DashboardEditChromeSnapshotTests: XCTestCase {

    // A factory 1×1 cell is about 201×96 on iPhone 17 Pro: two of them, over a full-width 2×1.
    // Padded, so the remove buttons, which overhang their cells, are captured whole.
    private let canvas: SwiftUISnapshotLayout = .fixed(width: 402 + 2 * Spacing.lg, height: 2 * 96 + 2 * Spacing.lg)

    private func makeRow(isEditing: Bool, scheme: ColorScheme) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                PaceWidget(speedMPS: 3.0, unit: .metric)
                    .dashboardEditCard(size: .oneByOne)
                    .dashboardRemoveButton(title: PaceDashboardWidget.title, size: .oneByOne) {}
                HeartRateWidget(bpm: 142, zone: 3, source: .bleStrap)
                    .dashboardEditCard(size: .oneByOne)
                    .dashboardRemoveButton(title: HeartRateDashboardWidget.title, size: .oneByOne) {}
            }
            .frame(height: 96)
            // Two columns scale to 95%, not 90%, so its sides inset as far as a 1×1's (#141 review).
            CadenceWidget(cadence: 88, cadenceHistory: [], averageCadence: 85, maxCadence: 102, size: .twoByOne)
                .dashboardEditCard(size: .twoByOne)
                .dashboardRemoveButton(title: CadenceDashboardWidget.title, size: .twoByOne) {}
                .frame(height: 96)
        }
        .frame(width: 402)
        .padding(Spacing.lg)
        .background(Color.cyBgSecondary)
        .environment(\.isEditingDashboard, isEditing)
        .preferredColorScheme(scheme)
    }

    func testDashboardEditChrome() {
        assertSnapshot(
            of: makeRow(isEditing: true, scheme: .light),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .light)),
            named: "light"
        )
        assertSnapshot(
            of: makeRow(isEditing: true, scheme: .dark),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .dark)),
            named: "dark"
        )
    }

    /// An empty cell's dashed slot (#368) beside a 1×1 card: the same size and inset, no glyph.
    private func makeEmptySlotRow(scheme: ColorScheme) -> some View {
        HStack(spacing: 0) {
            DashboardEmptySlot(cell: DashboardGrid.Cell(row: 0, column: 0)) {}
            PaceWidget(speedMPS: 3.0, unit: .metric)
                .dashboardEditCard(size: .oneByOne)
                .dashboardRemoveButton(title: PaceDashboardWidget.title, size: .oneByOne) {}
        }
        .frame(width: 402, height: 96)
        .padding(Spacing.lg)
        .background(Color.cyBgSecondary)
        .environment(\.isEditingDashboard, true)
        .preferredColorScheme(scheme)
    }

    func testDashboardEditChromeEmptySlot() {
        let canvas: SwiftUISnapshotLayout = .fixed(width: 402 + 2 * Spacing.lg, height: 96 + 2 * Spacing.lg)
        assertSnapshot(
            of: makeEmptySlotRow(scheme: .light),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .light)),
            named: "light"
        )
        assertSnapshot(
            of: makeEmptySlotRow(scheme: .dark),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .dark)),
            named: "dark"
        )
    }

    /// Outside edit mode the chrome adds nothing: no card, no button, full size.
    func testDashboardEditChromeOff() {
        assertSnapshot(
            of: makeRow(isEditing: false, scheme: .light),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .light)),
            named: "light"
        )
    }
}
