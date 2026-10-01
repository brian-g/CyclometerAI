import SwiftUI
import ComposableArchitecture

/// A widget the rider can place on the dashboard (UX.md §S05 "Widget Details"). Each widget
/// declares its own facts — its persisted id and the sizes it has a layout for — and reads what it
/// needs from the ride, beside its view in its own folder. The widget view itself keeps plain value
/// inputs, so it stays snapshot-testable without a store.
///
/// W7 Radar is not one: it is the full-height lane beside the grid on every page (PRD §8.2,
/// UX.md §S06), so it can't be placed, moved or removed.
protocol DashboardWidget: View {
    /// Saved in the rider's layout. Never rename one: a layout naming an id this build doesn't
    /// have drops that widget.
    static var id: String { get }
    /// The sizes this widget has a layout for. The validator rejects any other, and S08 (#142)
    /// filters its picker by them.
    static var supportedSizes: [WidgetSize] { get }

    init(size: WidgetSize, store: StoreOf<ActiveRideFeature>)
}

/// Every placeable widget. Swift can't discover conforming types at runtime, so adding a widget
/// is its `DashboardWidget` type plus one line here.
enum DashboardWidgetCatalog {
    static let all: [any DashboardWidget.Type] = [
        SpeedDashboardWidget.self,
        CadenceDashboardWidget.self,
        HeartRateDashboardWidget.self,
        HRZonesDashboardWidget.self,
        PaceDashboardWidget.self,
        DirectionsDashboardWidget.self,
        MapDashboardWidget.self,
    ]

    private static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func widget(id: String) -> (any DashboardWidget.Type)? { byID[id] }
}

extension DashboardWidget {
    /// This widget at `size`, type-erased so a page can hold any mix of widgets.
    static func view(size: WidgetSize, store: StoreOf<ActiveRideFeature>) -> AnyView {
        AnyView(Self(size: size, store: store))
    }
}
