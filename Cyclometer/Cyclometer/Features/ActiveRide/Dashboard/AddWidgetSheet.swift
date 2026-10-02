import SwiftUI
import ComposableArchitecture

/// S08 — Add Widget (#142), opened from S07 edit mode's Add. Every widget at every size it supports,
/// by category; an entry adds that widget to the page the rider is on, in its first open spot.
struct AddWidgetSheet: View {
    let store: StoreOf<ActiveRideFeature>
    /// The dashboard's full-screen size, which sets each preview's proportions.
    let canvas: CGSize

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                AddWidgetCatalog(
                    page: store.dashboardLayout.pages[store.visibleDashboardPage],
                    canvas: canvas,
                    onEmptyPage: { store.send(.addEmptyPageTapped, animation: .default) },
                    onAdd: { store.send(.addWidgetSelected(widgetID: $0.widget.id, size: $0.size), animation: .default) }
                )
            }
            .navigationTitle("Add Widget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
    }
}

/// One picker entry: a widget at one of its sizes.
struct AddWidgetEntry: Identifiable {
    let widget: any DashboardWidget.Type
    let size: WidgetSize

    var id: String { "\(widget.id)-\(size.rawValue)" }

    /// `category`'s entries, largest size first — every 2×2, then 2×1, then 1×1 — each size in
    /// catalog order.
    static func entries(in category: WidgetCategory) -> [AddWidgetEntry] {
        let widgets = DashboardWidgetCatalog.all.filter { $0.category == category }
        return [WidgetSize.twoByTwo, .twoByOne, .oneByOne].flatMap { size in
            widgets.filter { $0.supportedSizes.contains(size) }.map { AddWidgetEntry(widget: $0, size: size) }
        }
    }

    /// `entries` as the picker lays them out: a full-width entry alone, 1×1s two to a row.
    static func rows(_ entries: [AddWidgetEntry]) -> [[AddWidgetEntry]] {
        entries.reduce(into: []) { rows, entry in
            if entry.size.columns == 1, let last = rows.last, last.count == 1, last[0].size.columns == 1 {
                rows[rows.count - 1].append(entry)
            } else {
                rows.append([entry])
            }
        }
    }
}

/// The sheet's scrolling content, apart from its navigation chrome so it can be snapshotted.
struct AddWidgetCatalog: View {
    /// The page an entry would be added to: it dims what that page can't take.
    let page: DashboardPage
    let canvas: CGSize
    var categories = WidgetCategory.allCases
    let onEmptyPage: () -> Void
    let onAdd: (AddWidgetEntry) -> Void

    /// Previews show this sample ride, not the live one, so the picker reads the same whether or
    /// not sensors are up. The rider's units still apply, through `@Shared` preferences.
    @State private var sampleStore: StoreOf<ActiveRideFeature> = Store(initialState: .addWidgetSample) {
        EmptyReducer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            section("Page") {
                Button(action: onEmptyPage) {
                    Label("Empty page", systemImage: "plus.rectangle.portrait")
                        .foregroundStyle(Color.cyTextPrimary)
                }
                .buttonStyle(.plain)
                // From a blank page, another would only be pruned unused.
                .disabled(page.placements.isEmpty)
                .opacity(page.placements.isEmpty ? Opacity.unavailable : 1)
            }
            ForEach(categories, id: \.self) { category in
                let entries = AddWidgetEntry.entries(in: category)
                if !entries.isEmpty {
                    section(category.title) {
                        VStack(spacing: Spacing.md) {
                            ForEach(AddWidgetEntry.rows(entries), id: \.first?.id) { row in
                                HStack(spacing: Spacing.md) {
                                    ForEach(row) { entryButton($0) }
                                    // A lone 1×1 keeps a 1×1's width, its right-hand partner empty.
                                    if row.count == 1, row[0].size.columns == 1 {
                                        Color.clear.frame(maxWidth: .infinity)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.lg)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(title)
                .font(.title3)
                .foregroundStyle(Color.cyTextPrimary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func entryButton(_ entry: AddWidgetEntry) -> some View {
        let canAdd = page.firstOpenPlacement(widgetID: entry.widget.id, size: entry.size) != nil
        return Button { onAdd(entry) } label: {
            AddWidgetPreview(entry: entry, canvas: canvas, store: sampleStore)
        }
        .buttonStyle(.plain)
        .disabled(!canAdd)
        .opacity(canAdd ? 1 : Opacity.unavailable)
        .accessibilityLabel("\(entry.widget.title), \(entry.size.columns) by \(entry.size.rows)")
    }
}

/// A widget drawn at its real dashboard size and scaled down to the entry's width, so its type and
/// layout are the dashboard's, only smaller. Framed as S07 edit mode frames a widget (#141).
private struct AddWidgetPreview: View {
    let entry: AddWidgetEntry
    let canvas: CGSize
    let store: StoreOf<ActiveRideFeature>

    var body: some View {
        let native = DashboardGrid.frame(
            for: WidgetPlacement(widgetID: entry.widget.id, size: entry.size, row: 0, column: 0),
            in: canvas
        ).size
        let card = RoundedRectangle(cornerRadius: Spacing.cornerMd)
        Color.clear
            .aspectRatio(native, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    entry.widget.view(size: entry.size, store: store)
                        .frame(width: native.width, height: native.height)
                        .scaleEffect(proxy.size.width / native.width, anchor: .topLeading)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .background(Color.cyBgSecondary)
            .clipShape(card)
            .overlay(card.strokeBorder(Color.cyBorderStrong, lineWidth: Spacing.strokeHairline))
            .contentShape(card)
    }
}

extension ActiveRideFeature.State {
    /// The ride S08's previews show (#142): mid-ride, every sensor reading.
    static var addWidgetSample: Self {
        Self(
            recordingState: .active,
            elapsedSeconds: 2340,
            heartRateBPM: 155,
            hrZone: 4,
            isHRPaired: true,
            cadence: CadenceFeature.State(cadenceRPM: 87, pedalingSampleCount: 120, cadenceSum: 10_200, maxCadenceRPM: 102),
            distanceMeters: 12300,
            speed: SpeedFeature.State(speedMPS: 7.89, activeSpeedSource: .gps),
            maxSpeedKPH: 34.1,
            speedSampleCount: 120,
            speedSampleSum: 3408
        )
    }
}

#Preview {
    withDependencies {
        $0.defaultFileStorage = .inMemory
        $0.persistenceClient = .mock()
    } operation: {
        let store = Store(initialState: ActiveRideFeature.State(recordingState: .active)) {
            ActiveRideFeature()
        }
        store.send(.dashboardLongPressed)
        return AddWidgetSheet(store: store, canvas: CGSize(width: 402, height: 874))
    }
}
