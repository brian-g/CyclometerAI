import XCTest
import SnapshotTesting
import SwiftUI
import ComposableArchitecture
@testable import Cyclometer

/// S08's picker content (#142), in imperial units: the Page row, then the Ride, Heart, Fitness and Elevation
/// sections (#517) — widgets at every size, 2×2 first, 1×1s paired, every edge aligned. Pace is already
/// on the page, so its entry is dimmed. Route is left out: its Map entry is a live `Map`, which doesn't
/// snapshot stably. "collapsed" shows the Heart and Elevation sections collapsed.
///
/// The sheet's toolbar isn't part of this: toolbars don't render in a hosted snapshot.
final class AddWidgetSheetSnapshotTests: XCTestCase {

    /// Tall enough for the whole catalog expanded, or with Heart and Elevation collapsed.
    private static let expandedHeight: CGFloat = 2100
    private static let collapsedHeight: CGFloat = 1400

    private func makeCatalog(
        scheme: ColorScheme,
        collapsed: Set<WidgetCategory> = [],
        height: CGFloat = expandedHeight
    ) -> some View {
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
                    categories: [.ride, .heartRate, .fitness, .elevation],
                    collapsed: .constant(collapsed),
                    pairedRoles: Set(SensorRole.allCases),
                    onEmptyPage: {},
                    onAdd: { _ in }
                )
            }
            .frame(width: 402, height: height)
            .background(Color.cyBgPrimary)
            .preferredColorScheme(scheme)
        }
    }

    func testAddWidgetCatalog() {
        assertSnapshot(
            of: makeCatalog(scheme: .light),
            as: .image(layout: .fixed(width: 402, height: Self.expandedHeight), traits: .init(userInterfaceStyle: .light)),
            named: "light"
        )
        assertSnapshot(
            of: makeCatalog(scheme: .dark),
            as: .image(layout: .fixed(width: 402, height: Self.expandedHeight), traits: .init(userInterfaceStyle: .dark)),
            named: "dark"
        )
    }

    func testAddWidgetCatalogCollapsed() {
        assertSnapshot(
            of: makeCatalog(scheme: .light, collapsed: [.heartRate, .elevation], height: Self.collapsedHeight),
            as: .image(layout: .fixed(width: 402, height: Self.collapsedHeight), traits: .init(userInterfaceStyle: .light)),
            named: "light"
        )
    }
}
