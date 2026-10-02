import SwiftUI
import ComposableArchitecture

/// W5 Cadence on the dashboard.
struct CadenceDashboardWidget: DashboardWidget {
    static let id = "cadence"
    static let title = "Cadence"
    static let supportedSizes: [WidgetSize] = [.oneByOne, .twoByOne]

    let size: WidgetSize
    let store: StoreOf<ActiveRideFeature>

    var body: some View {
        CadenceWidget(
            cadence: store.cadence.cadenceRPM,
            cadenceHistory: store.cadence.watermarkSamples,
            averageCadence: store.cadence.averageCadenceRPM,
            maxCadence: store.cadence.maxCadenceRPM,
            detail: { CadenceDetail(cadence: store.cadence, altitudeSamples: store.altitudeSamples) },
            size: size
        )
    }
}
