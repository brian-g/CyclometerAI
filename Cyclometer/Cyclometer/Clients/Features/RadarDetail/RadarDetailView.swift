import SwiftUI
import ComposableArchitecture

struct RadarDetailView: View {
    let store: StoreOf<RadarDetailFeature>

    var body: some View {
        ZStack {
            Color.cyBgPrimary.ignoresSafeArea()

            if store.isRadarPaired {
                VStack {
                    Text("Radar Detail")
                        .font(.cyMetricMedium)
                        .foregroundStyle(Color.cyTextPrimary)
                    // TODO: Radar visualisation canvas
                    // (arc / linear strip / threat dots per PRD options)
                    ForEach(store.targets) { target in
                        Text("Vehicle @ \(Int(target.rangeMetre))m")
                            .foregroundStyle(Color.cyTextSecondary)
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.cyTextTertiary)
                    Text("No radar paired")
                        .font(.cyMetricSmall)
                        .foregroundStyle(Color.cyTextSecondary)
                    Button("Pair Varia Radar") {
                        store.send(.pairNewDeviceTapped)
                    }
                    .foregroundStyle(Color.cyPrimary)
                }
            }
        }
        .onAppear { store.send(.onAppear) }
    }
}
