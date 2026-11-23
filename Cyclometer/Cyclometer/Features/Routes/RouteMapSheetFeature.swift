import ComposableArchitecture
import Foundation

/// S20's full-screen map (#570): the route with pan and zoom, opened by tapping the map header, with
/// S15's one Map Options menu (#537) — the basemap, the forecast wind layer (#561), and the route
/// colored Plain or by Grade.
///
/// Holds what the map draws, copied from `RouteDetailFeature` when the sheet opens; the parent
/// keeps its wind current while it's open. The basemap is S15's, remembered
/// (`AppPreferences.rideMapBasemap`); the wind layer and the coloring start over each time it opens.
@Reducer
struct RouteMapSheetFeature {
    @ObservableState
    struct State: Equatable {
        /// For the map's framing, from the route's stored bounds.
        var summary: RouteSummary
        var coordinates: [RouteCoordinate]
        /// The forecast wind along the route for a ride starting now (#561).
        var wind: [WindSample]

        /// The rider's pick, shared with S15's map sheet and kept across relaunches.
        @Shared(.appPreferences) var preferences
        var basemap: MapBasemap { preferences.rideMapBasemap }
        var showsWind = true
        var coloring: RouteColoring = .plain
        /// The colored route and its legend, worked out when the coloring changes rather than on
        /// every draw. Empty for Plain.
        var coloredRuns: [ColoredRun] = []
        var legend: [RouteColorScale.LegendEntry] = []
        var legendUnit = ""

        init(summary: RouteSummary, coordinates: [RouteCoordinate], wind: [WindSample]) {
            self.summary = summary
            self.coordinates = coordinates
            self.wind = wind
        }

        /// Plain, then Grade for a route with elevation — the rule that shows S20's Elevation
        /// section, so the two never disagree about whether the route has any.
        var availableColorings: [RouteColoring] {
            [.plain] + (summary.elevationGainMeters != nil ? [.grade] : [])
        }

        mutating func recolor() {
            guard coloring == .grade,
                  let bands = RouteGradeBands.bands(coordinates) else {
                coloredRuns = []
                legend = []
                legendUnit = ""
                return
            }
            coloredRuns = RouteColorScale.runs(bandedSegments: [zip(coordinates, bands).map {
                (coordinate: $0, band: Optional($1))
            }])
            // Grade's legend reads neither the track nor the units.
            let scale = RouteColorScale(coloring: .grade, track: RideMapTrack(segments: []),
                                        heartRateZones: [], cadenceZones: .default)
            legend = scale.legend(.metric)
            legendUnit = scale.legendUnit(.metric)
        }
    }

    enum Action: Equatable {
        case basemapSelected(MapBasemap)
        case windToggled(Bool)
        case coloringSelected(RouteColoring)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .basemapSelected(let basemap):
                state.$preferences.withLock { $0.rideMapBasemap = basemap }
                return .none
            case .windToggled(let isOn):
                state.showsWind = isOn
                return .none
            case .coloringSelected(let coloring):
                guard state.availableColorings.contains(coloring) else { return .none }
                state.coloring = coloring
                state.recolor()
                return .none
            }
        }
    }
}

/// Each point of a route in S15's grade bands (#570), from the grades S20 already quotes: the same
/// resampled, creek-filled, smoothed profile behind Max Grade and the climbs
/// (`RouteTerrain.gradeProfile`), so the map's colors and the numbers beside them can't disagree.
/// A route's elevation is a terrain model's bare earth, which is why the creek fill applies here
/// and not to a ride's barometer (#533).
enum RouteGradeBands {
    /// One band per coordinate, 1 to 5; nil for a route with no length or no elevation. Descents
    /// are flat, as on S15: the ramp says how hard the road is to climb.
    static func bands(_ coordinates: [RouteCoordinate]) -> [Int]? {
        guard let profile = RouteTerrain.gradeProfile(coordinates), !profile.grades.isEmpty else { return nil }
        let grades = profile.grades
        let cumulative = RouteGeometry.cumulativeDistances(coordinates)
        return cumulative.map { distance in
            let index = min(grades.count - 1, max(0, Int((distance / profile.spacing).rounded())))
            return RouteColorScale.gradeBand(grades[index])
        }
    }
}
