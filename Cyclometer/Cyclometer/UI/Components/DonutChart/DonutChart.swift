import Charts
import SwiftUI

struct DonutSlice: Identifiable {
    let id: String
    let value: TimeInterval
    let color: Color
}

/// Share of time per slice. Purely decorative: the rows beside it carry the values.
struct DonutChart: View {
    let slices: [DonutSlice]

    private static let innerRadiusRatio = 0.6

    var body: some View {
        Chart(slices.filter { $0.value > 0 }) { slice in
            SectorMark(
                angle: .value("Time", slice.value),
                innerRadius: .ratio(Self.innerRadiusRatio),
                angularInset: 1
            )
            .foregroundStyle(slice.color)
        }
        .chartLegend(.hidden)
        .accessibilityHidden(true)
    }
}
