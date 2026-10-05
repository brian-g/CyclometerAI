import SwiftUI
import ComposableArchitecture

/// S08 — Add Widget (#142), opened from S07 edit mode's Add. Every widget at every size it supports,
/// by category; an entry adds that widget to the page the rider is on, in its first open spot.
/// Opened from an empty cell instead (#368), it lists only the sizes that fit with that cell as
/// their top-left, and adds there.
struct AddWidgetSheet: View {
    let store: StoreOf<ActiveRideFeature>
    /// The dashboard grid's size — the screen, less the radar lane when it shows — which sets
    /// each preview's proportions.
    let canvas: CGSize

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                AddWidgetCatalog(
                    page: store.dashboardLayout.pages[store.visibleDashboardPage],
                    cell: store.addWidgetCell,
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
    /// The empty cell the sheet was opened from (#368), or `nil` from Add.
    var cell: DashboardGrid.Cell? = nil
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
            // A page isn't something a cell can hold.
            if cell == nil {
                section("Page") {
                    Button(action: onEmptyPage) {
                        Label("Empty page", systemImage: "text.rectangle.page")
                            .foregroundStyle(Color.cyTextPrimary)
                            // The whole row, a full tap target tall: the label alone is a ~22 pt target.
                            .frame(maxWidth: .infinity, minHeight: Spacing.tapTarget, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // From a blank page, another would only be pruned unused.
                    .disabled(page.placements.isEmpty)
                    .opacity(page.placements.isEmpty ? Opacity.unavailable : 1)
                }
            }
            ForEach(categories, id: \.self) { category in
                // From a cell, only the sizes that fit with it as their top-left.
                let entries = AddWidgetEntry.entries(in: category).filter { entry in
                    cell.map { page.fits(entry.size, at: $0) } ?? true
                }
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
        let canAdd = page.openPlacement(widgetID: entry.widget.id, size: entry.size, at: cell) != nil
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
        // Nothing to scale until the dashboard has been measured; a zero size would scale by ∞.
        if native.width > 0, native.height > 0 {
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
            speed: SpeedFeature.State(speedMPS: 7.89, activeSpeedSource: .gps, speedSamples: SpeedSample.sampleHour),
            maxSpeedMPS: 9.47,
            speedSampleCount: 1560,
            averageSpeedSamples: SpeedSample.sampleHourAverage
        )
    }
}

extension SpeedSample {
    /// A sample hour, one reading a minute, that builds then fades — so S08's speed previews draw
    /// their watermarks, and W2's line both climbs and falls (#140). Also W2's previews and snapshots.
    static let sampleHour: [SpeedSample] = (0..<60).map { minute in
        let mps = minute < 40 ? 6 + Double(minute) * 0.08 : 9.2 - Double(minute - 40) * 0.115
        return SpeedSample(time: Date(timeIntervalSinceReferenceDate: Double(minute) * 60), mps: mps)
    }

    /// The ride average at each of `sampleHour`'s readings.
    static let sampleHourAverage: [SpeedSample] = sampleHour.indices.map { i in
        let sofar = sampleHour[...i]
        return SpeedSample(time: sampleHour[i].time, mps: sofar.reduce(0) { $0 + $1.mps } / Double(sofar.count))
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
        store.send(.addWidgetTapped)
        return AddWidgetSheet(store: store, canvas: CGSize(width: 402, height: 874))
    }
}
