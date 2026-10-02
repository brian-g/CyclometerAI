import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

/// S07 edit mode's per-widget chrome (#141): the 0.90 card with its hairline border, and the remove
/// button centred on the card's corner. Two 1×1 widgets side by side, so the gap between
/// neighbouring cards is pinned too.
///
/// The wiggle is a separate modifier and isn't applied here: each capture would catch a different
/// angle.
final class DashboardEditChromeSnapshotTests: XCTestCase {

    // A factory 1×1 cell is about 201×96 on iPhone 17 Pro. Padded, so the remove buttons, which
    // overhang their cells, are captured whole.
    private let canvas: SwiftUISnapshotLayout = .fixed(width: 402 + 2 * Spacing.lg, height: 96 + 2 * Spacing.lg)

    private func makeRow(isEditing: Bool, scheme: ColorScheme) -> some View {
        HStack(spacing: 0) {
            PaceWidget(speedMPS: 3.0, unit: .metric)
                .dashboardEditCard()
                .dashboardRemoveButton(title: PaceDashboardWidget.title) {}
            HeartRateWidget(bpm: 142, zone: 3, source: .bleStrap)
                .dashboardEditCard()
                .dashboardRemoveButton(title: HeartRateDashboardWidget.title) {}
        }
        .frame(width: 402, height: 96)
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

    /// Outside edit mode the chrome adds nothing: no card, no button, full size.
    func testDashboardEditChromeOff() {
        assertSnapshot(
            of: makeRow(isEditing: false, scheme: .light),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .light)),
            named: "light"
        )
    }
}
