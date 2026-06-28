import Charts
import SwiftUI

// MARK: - W5 Cadence Widget

struct CadenceWidget: View {
    let cadence: Int?            // rpm; nil → "—"
    let cadenceHistory: [Double] // rpm samples for watermark chart
    let averageCadence: Int      // rpm; 0 → no pedalling recorded yet
    let maxCadence: Int          // rpm
    var size: WidgetSize = .twoByOne   // only .oneByOne / .twoByOne used by W5

    @State private var showDetail = false

    var body: some View {
        ZStack {
            if !cadenceHistory.isEmpty {
                CadenceHistoryChart(history: cadenceHistory)
            }
            switch size {
            case .oneByOne, .twoByTwo: oneByOneContent
            case .twoByOne:            twoByOneContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cyBgSecondary)
        .contentShape(Rectangle())
        .onTapGesture { showDetail = true }
        .sheet(isPresented: $showDetail) {
            CadenceDetailSheet(maxCadence: maxCadence)
        }
    }

    // MARK: - Layout Variants

    private var oneByOneContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel("Cadence")
            cadenceHero
            Spacer()
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var twoByOneContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel("Cadence")
            HStack(alignment: .lastTextBaseline, spacing: Spacing.lg) {
                cadenceHero
                Spacer()
                avgStat
                maxStat
            }
            Spacer()
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sub-Views

    // Current value reuses the design-system HeroNumber at medium-hero (68pt),
    // matching the sibling 1×1 widgets (HR, Pace). Unit shown only when paired.
    private var cadenceHero: some View {
        HeroNumber(displayCadence, unit: cadence != nil ? "rpm" : "")
            .heroNumberSize(.medium)
    }

    // Stat cells reuse the design-system HeroNumber, matching SpeedWidget.
    private var avgStat: some View {
        HeroNumber(displayAvg, unit: "") { Text("Avg").font(.caption) }
            .heroNumberSize(.small)
            .layout(.vertical)
    }

    private var maxStat: some View {
        HeroNumber(displayMax, unit: "") { Text("Max").font(.caption) }
            .heroNumberSize(.small)
            .layout(.vertical)
    }

    // MARK: - Computed Display Values

    private var displayCadence: String { cadence.map(String.init) ?? "—" }
    /// Avg/Max read "—" until at least one pedalling reading exists (0 rpm average
    /// is meaningless — it would mean the rider never pedalled).
    private var displayAvg: String { averageCadence > 0 ? "\(averageCadence)" : "—" }
    private var displayMax: String { maxCadence > 0 ? "\(maxCadence)" : "—" }
}

// MARK: - Cadence History Watermark Chart

private struct CadenceHistoryChart: View {
    let history: [Double]   // rpm

    /// Fixed y-domain so the zone bands always map to the same screen positions
    /// regardless of the ride's actual cadence range. 150 covers sprint/over-spin
    /// cadences so the line and red over-spin band aren't clipped above 130.
    private static let yMax: Double = 150

    var body: some View {
        Chart {
            // Coloured zone bands behind the cadence line (issue #38).
            ForEach(Array(CadenceZone.allCases.enumerated()), id: \.offset) { _, zone in
                let range = zone.rpmRange(ceiling: Self.yMax)
                RectangleMark(
                    xStart: .value("t0", 0),
                    xEnd: .value("t1", max(history.count - 1, 1)),
                    yStart: .value("rpm0", range.lowerBound),
                    yEnd: .value("rpm1", range.upperBound)
                )
                .foregroundStyle(zone.color.opacity(Opacity.zoneBand))
            }

            // Cadence trace as a line over the bands. No area fill — it would tint
            // the lower (grinding/optimal) bands and defeat the at-a-glance read.
            ForEach(Array(history.enumerated()), id: \.offset) { index, rpm in
                LineMark(x: .value("t", index), y: .value("rpm", rpm))
                    .foregroundStyle(Color.cyTextPrimary.opacity(Opacity.lineWatermark))
            }
        }
        .chartYScale(domain: 0...Self.yMax)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}

// MARK: - Cadence Detail Sheet (stub)

/// Stub modal for the W5 "Ride metrics" sheet (UX.md §W5). Lists the planned
/// cadence breakdowns; values arrive once a BLE cadence/power source is wired
/// (M2/M6). Mirrors SpeedWidget's placeholder sheet.
private struct CadenceDetailSheet: View {
    let maxCadence: Int

    var body: some View {
        NavigationStack {
            List {
                metricRow("Max Cadence", maxCadence > 0 ? "\(maxCadence) rpm" : "—")
                metricRow("Pedaling vs Coasting", "—")
                Section("Time in Cadence Zones") {
                    ForEach(CadenceZone.allCases, id: \.self) { zone in
                        metricRow("\(zone.label) rpm", "—")
                    }
                }
                metricRow("Cadence Smoothness", "—")
            }
            .navigationTitle("Cadence")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        LabeledContent(label, value: value)
    }
}

// MARK: - Previews

private let demoHistory: [Double] = stride(from: 60.0, to: 105.0, by: 1.2).map { $0 }

#Preview("2×1 — Active") {
    CadenceWidget(
        cadence: 92,
        cadenceHistory: demoHistory,
        averageCadence: 88,
        maxCadence: 104,
        size: .twoByOne
    )
    .frame(width: 393, height: 96)
}

#Preview("2×1 — No Signal") {
    CadenceWidget(
        cadence: nil,
        cadenceHistory: [],
        averageCadence: 0,
        maxCadence: 0,
        size: .twoByOne
    )
    .frame(width: 393, height: 96)
}

#Preview("1×1 — Active") {
    CadenceWidget(
        cadence: 92,
        cadenceHistory: [],
        averageCadence: 88,
        maxCadence: 104,
        size: .oneByOne
    )
    .frame(width: 196, height: 96)
}

#Preview("1×1 — No Signal") {
    CadenceWidget(
        cadence: nil,
        cadenceHistory: [],
        averageCadence: 0,
        maxCadence: 0,
        size: .oneByOne
    )
    .frame(width: 196, height: 96)
}
