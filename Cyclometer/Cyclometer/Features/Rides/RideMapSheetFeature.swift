import ComposableArchitecture
import Foundation

/// S15's full-screen map (#538): the route with pan and zoom, opened by tapping the map header,
/// with a choice of basemap, the vehicle-pass and stop layers, and route coloring (#537).
///
/// Holds what the map draws, copied from `RideDetailFeature` when the sheet opens; the parent
/// keeps the passes and heart rate zones current while it's open. The basemap is remembered
/// (`AppPreferences.rideMapBasemap`); the layers and coloring start over each time it opens.
@Reducer
struct RideMapSheetFeature {
    @ObservableState
    struct State: Equatable {
        /// One polyline per stretch of riding, as the header draws them: the Plain coloring.
        var segments: [[RouteCoordinate]]
        var track: RideMapTrack
        var passes: [VehiclePassEventDTO]
        var stops: [RideStop]
        var unitSystem: UnitSystem
        /// A radar was paired. Without one there is no pass layer to offer, as S15 shows no
        /// Vehicle Passes row.
        var hasRadar: Bool
        var heartRateZones: [ClosedRange<Int>]
        var cadenceZones: CadenceZoneBoundaries

        /// The rider's pick, kept across rides and relaunches.
        @Shared(.appPreferences) var preferences
        var basemap: MapBasemap { preferences.rideMapBasemap }
        var showsPasses = true
        var showsStops = true
        var coloring: RouteColoring = .plain
        /// The colored route and its legend, worked out when the coloring or the zones change
        /// rather than on every draw. Empty for Plain.
        var coloredRuns: [ColoredRun] = []
        var legend: [RouteColorScale.LegendEntry] = []
        var legendUnit = ""

        init(segments: [[RouteCoordinate]], track: RideMapTrack = RideMapTrack(segments: []),
             passes: [VehiclePassEventDTO], stops: [RideStop] = [], unitSystem: UnitSystem,
             hasRadar: Bool = true, heartRateZones: [ClosedRange<Int>] = [],
             cadenceZones: CadenceZoneBoundaries = .default) {
            self.segments = segments
            self.track = track
            self.passes = passes
            self.stops = stops
            self.unitSystem = unitSystem
            self.hasRadar = hasRadar
            self.heartRateZones = heartRateZones
            self.cadenceZones = cadenceZones
        }

        /// Plain, then each metric the ride recorded: no cadence or heart rate option without
        /// the sensor, and no grade without altitude.
        var availableColorings: [RouteColoring] {
            [.plain]
                + (track.hasSpeed ? [.speed] : [])
                + (track.hasGrade ? [.grade] : [])
                + (track.hasCadence ? [.cadence] : [])
                + (track.hasHeartRate ? [.heartRate] : [])
        }

        mutating func recolor() {
            guard coloring != .plain else {
                coloredRuns = []
                legend = []
                legendUnit = ""
                return
            }
            let scale = RouteColorScale(coloring: coloring, track: track, heartRateZones: heartRateZones,
                                        cadenceZones: cadenceZones)
            coloredRuns = scale.runs(track)
            legend = scale.legend(unitSystem)
            legendUnit = scale.legendUnit(unitSystem)
        }
    }

    enum Action: Equatable {
        case basemapSelected(MapBasemap)
        case passesToggled(Bool)
        case stopsToggled(Bool)
        case coloringSelected(RouteColoring)
        /// Health's zones landed after the sheet opened.
        case heartRateZonesChanged([ClosedRange<Int>])
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .basemapSelected(let basemap):
                state.$preferences.withLock { $0.rideMapBasemap = basemap }
                return .none
            case .passesToggled(let isOn):
                state.showsPasses = isOn
                return .none
            case .stopsToggled(let isOn):
                state.showsStops = isOn
                return .none
            case .coloringSelected(let coloring):
                guard state.availableColorings.contains(coloring) else { return .none }
                state.coloring = coloring
                state.recolor()
                return .none
            case .heartRateZonesChanged(let zones):
                guard zones != state.heartRateZones else { return .none }
                state.heartRateZones = zones
                if state.coloring == .heartRate { state.recolor() }
                return .none
            }
        }
    }
}

/// S15's vehicle-pass sheet (#538): each pass's time and the vehicle's speed. Rows aren't
/// tappable, so there is nothing to act on.
@Reducer
struct RidePassesFeature {
    @ObservableState
    struct State: Equatable {
        /// Oldest first, as `RideDetailFeature` holds them.
        var passes: [VehiclePassEventDTO]
        var unitSystem: UnitSystem
    }

    enum Action: Equatable {}

    var body: some ReducerOf<Self> {
        EmptyReducer()
    }
}
