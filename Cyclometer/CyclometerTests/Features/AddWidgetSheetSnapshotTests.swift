import XCTest
import SnapshotTesting
import SwiftUI
import ComposableArchitecture
@testable import Cyclometer

/// S08's picker content (#142), in imperial units: the Page row, then the Ride and Heart Rate sections — widgets at
/// every size, 2×2 first, 1×1s paired, every edge aligned. Pace is already on the page, so its entry
/// is dimmed. Route is left out: its Map entry is a live `Map`, which doesn't snapshot stably.
///
/// The sheet's toolbar isn't part of this: toolbars don't render in a hosted snapshot.
final class AddWidgetSheetSnapshotTests: XCTestCase {

    private let canvas: SwiftUISnapshotLayout = .fixed(width: 402, height: 1040)

    private func makeCatalog(scheme: ColorScheme) -> some View {
        withDependencies {
            $0.defaultFileStorage = .inMemory
        } operation: {
            // Pinned: the sample store reads the rider's units, which otherwise follow the locale.
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.preferredUnit = .imperial }
            // In a scroll view, as in the sheet: a bounded height would shrink the previews.
            return ScrollView {
                AddWidgetCatalog(
                    page: DashboardPage(placements: [WidgetPlacement(PaceDashboardWidget.self, size: .oneByOne, row: 0, column: 0)]),
                    canvas: CGSize(width: 402, height: 874),
                    categories: [.ride, .heartRate],
                    onEmptyPage: {},
                    onAdd: { _ in }
                )
            }
            .frame(width: 402, height: 1040)
            .background(Color.cyBgPrimary)
            .preferredColorScheme(scheme)
        }
    }

    func testAddWidgetCatalog() {
        assertSnapshot(
            of: makeCatalog(scheme: .light),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .light)),
            named: "light"
        )
        assertSnapshot(
            of: makeCatalog(scheme: .dark),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .dark)),
            named: "dark"
        )
    }
}
