import SwiftUI
import ComposableArchitecture

/// W5 Cadence on the dashboard.
struct CadenceDashboardWidget: DashboardWidget {
    static let id = "cadence"
    static let title = "Cadence"
    static let supportedSizes: [WidgetSize] = [.oneByOne, .twoByOne]
    static let category = WidgetCategory.ride
    /// Only a crank sensor reads cadence, so S08 lists W5 only with one paired (#517).
    static let requiredSensor: SensorRole? = .cadence

    let size: WidgetSize
    let store: StoreOf<ActiveRideFeature>

    var body: some View {
        CadenceWidget(
            cadence: store.cadence.cadenceRPM,
            cadenceHistory: store.cadenceWatermark,
            watermarkWindow: store.watermarkWindow,
            averageCadence: store.cadence.averageCadenceRPM,
            maxCadence: store.cadence.maxCadenceRPM,
            zones: store.cadence.preferences.cadenceZones,
            detail: { CadenceDetail(cadence: store.cadence, altitudeSamples: store.altitudeSamples) },
            size: size
        )
    }
}
