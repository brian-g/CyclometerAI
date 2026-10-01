import SwiftUI
import ComposableArchitecture

/// The widget for one `WidgetKind` at one size, fed from the ride (#139). The one place that
/// knows which store fields each widget reads, so its body observes only those.
struct DashboardWidgetView: View {
    let kind: WidgetKind
    let size: WidgetSize
    let store: StoreOf<ActiveRideFeature>

    var body: some View {
        switch kind {
        case .speed:
            SpeedWidget(
                speed: store.speed.speedMPS,
                speedHistory: store.speed.watermarkSamples,
                activeSpeedSource: store.speed.activeSpeedSource,
                distance: store.distanceMeters,
                elapsed: store.elapsedSeconds,
                averageSpeed: store.averageSpeedMPS,
                maxSpeed: store.maxSpeedMPS,
                unit: store.unitSystem,
                size: size
            )
        case .cadence:
            CadenceWidget(
                cadence: store.cadence.cadenceRPM,
                cadenceHistory: store.cadence.watermarkSamples,
                averageCadence: store.cadence.averageCadenceRPM,
                maxCadence: store.cadence.maxCadenceRPM,
                detail: { CadenceDetail(cadence: store.cadence, altitudeSamples: store.altitudeSamples) },
                size: size
            )
        case .heartRate:
            HeartRateWidget(
                bpm: store.displayHeartRateBPM,
                zone: store.displayHRZone,
                source: store.hrSource
            )
        case .hrZones:
            HRZonesWidget(zone: store.displayHRZone, source: store.hrSource)
        case .pace:
            PaceWidget(speedMPS: store.speed.speedMPS ?? 0, unit: store.unitSystem)
        case .directions:
            directionsWidget
        case .map:
            mapWidget
        }
    }

    /// The map sheet's shared inputs (#199, #200) — W8 and W9 open the same sheet, so both
    /// widgets must carry it the same orientation and the same toggle action.
    ///
    /// Factored out, not just documented as "the same": Xcode's preview canvas instruments
    /// this file's `#Preview`-target build with a click-to-select wrapper on every
    /// subexpression, and two initializer calls repeating this exact argument shape
    /// verbatim (`mapWidget` and `directionsWidget`, both built from `route:`/
    /// `sheetOrientation:`/`onOrientationToggle:`) made that wrapper unable to tell the
    /// two apart — "ambiguous use of '__designTimeSelection'", which is what actually made
    /// the dashboard preview time out. Routing both through one shared getter/action
    /// removes the duplicate text, not just the duplicate logic.
    private var mapSheetRoute: [RouteCoordinate] {
        store.navigation.activeRoute?.coordinates ?? []
    }
    private var mapSheetOrientation: MapOrientation { store.preferences.mapOrientation }
    private func toggleMapOrientation() { store.send(.mapOrientationToggled) }

    /// W8: the track, the route being ridden (#199), and the sheet's saved orientation with the
    /// action that switches it.
    private var mapWidget: MapWidget {
        MapWidget(
            trackSegments: store.trackSegments,
            route: mapSheetRoute,
            sheetOrientation: mapSheetOrientation,
            onOrientationToggle: { toggleMapOrientation() },
            size: size
        )
    }

    /// W9 (#200). Its tap opens W8's map sheet, so it carries the same sheet inputs as `mapWidget`.
    private var directionsWidget: DirectionsWidget {
        DirectionsWidget(
            hasRoute: store.navigation.activeRoute != nil,
            nextTurn: store.navigation.nextManeuver,
            distanceMeters: store.navigation.distanceToNextTurnMeters,
            unit: store.unitSystem,
            size: size,
            trackSegments: store.trackSegments,
            route: mapSheetRoute,
            sheetOrientation: mapSheetOrientation,
            onOrientationToggle: { toggleMapOrientation() }
        )
    }
}
