import ComposableArchitecture
import Foundation
import Testing
@testable import Cyclometer

/// Synthetic routes for S20's map sheet and wind shares (#570): straight lines of points about
/// 11 m apart, north from the equator at the prime meridian.
private enum NorthRouteFixtures {
    /// One step north, in degrees: about 11.1 m.
    static let step = 0.0001

    /// `count` points due north, each `rise` metres above the last.
    static func north(count: Int, rise: Double? = 0) -> [RouteCoordinate] {
        (0..<count).map { index in
            RouteCoordinate(latitude: Double(index) * step, longitude: 0,
                            elevationMeters: rise.map { 100 + Double(index) * $0 })
        }
    }

    /// Out due north for `count` points, then back the same way.
    static func outAndBack(count: Int) -> [RouteCoordinate] {
        let out = north(count: count, rise: nil)
        return out + out.reversed().dropFirst()
    }

    /// A summary for `coordinates`, with a gain only when they carry elevation.
    static func summary(_ coordinates: [RouteCoordinate]) -> RouteSummary {
        var summary = RouteSummary.previewRoutes[1]
        summary.distanceMeters = RouteGeometry.distanceMeters(coordinates)
        summary.elevationGainMeters = RouteGeometry.elevationGainLoss(coordinates)?.gain
        summary.elevationLossMeters = RouteGeometry.elevationGainLoss(coordinates)?.loss
        return summary
    }

    /// The fixture's conditions with the wind from `degrees` at `mps`.
    static func reading(windFrom degrees: Double, mps: Double = 5) -> WeatherReading {
        var reading = WeatherReading.fixture
        reading.windDirection = Measurement(value: degrees, unit: .degrees)
        reading.windSpeed = Measurement(value: mps, unit: .metersPerSecond)
        return reading
    }
}

// MARK: - Sheet

/// #570 — S20's map sheet's options.
@MainActor
@Suite("RouteMapSheetFeature")
struct RouteMapSheetFeatureTests {
    /// About 1.1 km climbing at 10 %.
    private nonisolated static let climb = NorthRouteFixtures.north(count: 100, rise: 1.11)

    private func makeStore(coordinates: [RouteCoordinate] = Self.climb,
                           storage: FileStorage = .inMemory) -> TestStoreOf<RouteMapSheetFeature> {
        withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            TestStore(initialState: RouteMapSheetFeature.State(
                summary: NorthRouteFixtures.summary(coordinates), coordinates: coordinates, wind: []
            )) {
                RouteMapSheetFeature()
            } withDependencies: {
                $0.defaultFileStorage = storage
            }
        }
    }

    @Test("a route with elevation offers Plain and Grade; one without, Plain alone")
    func coloringsFollowTheElevation() {
        #expect(makeStore().state.availableColorings == [.plain, .grade])
        #expect(makeStore(coordinates: NorthRouteFixtures.north(count: 100, rise: nil)).state.availableColorings == [.plain])
    }

    @Test("choosing Grade colors the route by its grade bands with the grade legend; Plain takes both away")
    func gradeRecolors() async {
        let store = makeStore()
        let scale = RouteColorScale(coloring: .grade, track: RideMapTrack(segments: []), heartRateZones: [],
                                    cadenceZones: .default)
        await store.send(.coloringSelected(.grade)) {
            $0.coloring = .grade
            $0.coloredRuns = RouteColorScale.runs(bandedSegments: [
                zip(Self.climb, RouteGradeBands.bands(Self.climb)!).map { (coordinate: $0, band: Optional($1)) },
            ])
            $0.legend = scale.legend(.metric)
            $0.legendUnit = "%"
        }
        // 10 % is the 9–12 band. The first metres read shallower: the profile's 100 m grade window
        // hangs off the route's start there, as it does for Max Grade and the climbs.
        let runs = store.state.coloredRuns
        #expect(runs.last?.band == 4)
        let steep = runs.filter { $0.band == 4 }.map { RouteGeometry.distanceMeters($0.coordinates) }.reduce(0, +)
        #expect(steep >= 0.9 * RouteGeometry.distanceMeters(Self.climb))

        await store.send(.coloringSelected(.plain)) {
            $0.coloring = .plain
            $0.coloredRuns = []
            $0.legend = []
            $0.legendUnit = ""
        }
    }

    @Test("Grade can't be chosen on a route with no elevation")
    func unavailableColoringIsIgnored() async {
        let store = makeStore(coordinates: NorthRouteFixtures.north(count: 100, rise: nil))
        await store.send(.coloringSelected(.grade))
    }

    @Test("the wind layer starts on, and turns off and on")
    func windToggles() async {
        let store = makeStore()
        #expect(store.state.showsWind)
        await store.send(.windToggled(false)) { $0.showsWind = false }
        await store.send(.windToggled(true)) { $0.showsWind = true }
    }

    @Test("the basemap is S15's: picked here, it is what S15's sheet opens on")
    func basemapIsSharedWithS15() async {
        let storage = FileStorage.inMemory
        let store = makeStore(storage: storage)
        await store.send(.basemapSelected(.hybrid)) {
            $0.$preferences.withLock { $0.rideMapBasemap = .hybrid }
        }
        let rideSheet = withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            RideMapSheetFeature.State(segments: [], passes: [], unitSystem: .metric)
        }
        #expect(rideSheet.basemap == .hybrid)
    }
}

// MARK: - Grade bands

@Suite("RouteGradeBands")
struct RouteGradeBandsTests {
    @Test("each point takes the band of the profile's grade where it lies, as Max Grade reads it")
    func bandsFollowTheGradeProfile() throws {
        let coordinates = NorthRouteFixtures.north(count: 60, rise: 0) + NorthRouteFixtures.north(count: 60, rise: 1.11)
            .map { RouteCoordinate(latitude: $0.latitude + 60 * NorthRouteFixtures.step, longitude: 0,
                                   elevationMeters: $0.elevationMeters) }
        let bands = try #require(RouteGradeBands.bands(coordinates))
        let profile = try #require(RouteTerrain.gradeProfile(coordinates))
        let cumulative = RouteGeometry.cumulativeDistances(coordinates)
        #expect(bands.count == coordinates.count)
        for (index, band) in bands.enumerated() {
            let sample = min(profile.grades.count - 1, Int((cumulative[index] / profile.spacing).rounded()))
            #expect(band == RouteColorScale.gradeBand(profile.grades[sample]))
        }
        #expect(bands.first == 1, "flat at the start")
        #expect(bands[bands.count - 20] == 4, "10 % on the climb")
    }

    @Test("a route with no elevation, or no length, has no bands")
    func noElevationNoBands() {
        #expect(RouteGradeBands.bands(NorthRouteFixtures.north(count: 50, rise: nil)) == nil)
        #expect(RouteGradeBands.bands([]) == nil)
    }

    @Test("a descent is flat, as on S15")
    func descentIsFlat() throws {
        let bands = try #require(RouteGradeBands.bands(NorthRouteFixtures.north(count: 100, rise: -1.11)))
        #expect(Set(bands) == [1])
    }
}

// MARK: - Wind along a route

@Suite("RideWindExposure — along a route")
struct RouteWindExposureTests {
    /// About 2.2 km north.
    private static let north = NorthRouteFixtures.north(count: 200, rise: nil)

    @Test("riding north into a north wind is all headwind; with a south wind, all tailwind; with a west wind, all crosswind")
    func straightRoute() {
        func shares(_ degrees: Double) -> RideWindExposure? {
            RideWindExposure.alongRoute(Self.north, samples: [
                WindSample(coordinate: Self.north[0], reading: NorthRouteFixtures.reading(windFrom: degrees), distanceMeters: 0),
            ])
        }
        #expect(shares(0) == .shares(headwind: 100, crosswind: 0, tailwind: 0))
        #expect(shares(180) == .shares(headwind: 0, crosswind: 0, tailwind: 100))
        #expect(shares(270) == .shares(headwind: 0, crosswind: 100, tailwind: 0))
    }

    @Test("an out-and-back in one wind splits evenly into headwind and tailwind")
    func outAndBackOneWind() throws {
        let route = NorthRouteFixtures.outAndBack(count: 200)
        let exposure = try #require(RideWindExposure.alongRoute(route, samples: [
            WindSample(coordinate: route[0], reading: NorthRouteFixtures.reading(windFrom: 0), distanceMeters: 0),
        ]))
        guard case let .shares(headwind, crosswind, tailwind) = exposure else {
            Issue.record("expected shares, got \(exposure)")
            return
        }
        #expect(abs(headwind - tailwind) <= 2)
        #expect(crosswind <= 2, "only the turn")
    }

    /// The way home passes the same ground as the way out, so only the distance along the route says
    /// which sample a stretch takes.
    @Test("each stretch takes the sample at or before it along the route, so the way home takes the later wind")
    func samplesAreTimedByDistance() throws {
        let route = NorthRouteFixtures.outAndBack(count: 200)
        let cumulative = RouteGeometry.cumulativeDistances(route)
        let turn = 199
        // A north wind on the way out, then it swings round to the south for the way home: into
        // the wind both ways.
        let exposure = try #require(RideWindExposure.alongRoute(route, samples: [
            WindSample(coordinate: route[0], reading: NorthRouteFixtures.reading(windFrom: 0), distanceMeters: 0),
            WindSample(coordinate: route[turn], reading: NorthRouteFixtures.reading(windFrom: 180),
                       distanceMeters: cumulative[turn]),
        ]))
        guard case let .shares(headwind, _, tailwind) = exposure else {
            Issue.record("expected shares, got \(exposure)")
            return
        }
        #expect(headwind >= 98)
        #expect(tailwind == 0)
    }

    @Test("a wind too light to have a direction is calm")
    func calm() {
        #expect(RideWindExposure.alongRoute(Self.north, samples: [
            WindSample(coordinate: Self.north[0], reading: NorthRouteFixtures.reading(windFrom: 0, mps: 0.2), distanceMeters: 0),
        ]) == .calm)
    }

    @Test("no samples, or a route too short for a bearing, has no shares")
    func nothingToMeasure() {
        let sample = WindSample(coordinate: Self.north[0], reading: NorthRouteFixtures.reading(windFrom: 0), distanceMeters: 0)
        #expect(RideWindExposure.alongRoute(Self.north, samples: []) == nil)
        #expect(RideWindExposure.alongRoute(Array(Self.north.prefix(1)), samples: [sample]) == nil)
        // Under `TimedHeading.baselineMeters` end to end.
        #expect(RideWindExposure.alongRoute(Array(Self.north.prefix(2)), samples: [sample]) == nil)
    }
}

// MARK: - S20 and its sheet

/// What S20 hands its map sheet (#570), and keeps current while it's open.
@MainActor
@Suite("RouteDetailFeature — map sheet")
struct RouteDetailMapSheetTests {
    private nonisolated static let route = NorthRouteFixtures.north(count: 200, rise: 0.5)
    private static let samples = [
        WindSample(coordinate: route[0], reading: NorthRouteFixtures.reading(windFrom: 0), distanceMeters: 0),
        WindSample(coordinate: route[150], reading: NorthRouteFixtures.reading(windFrom: 270),
                   distanceMeters: RouteGeometry.cumulativeDistances(route)[150]),
    ]

    private func makeStore(coordinates: [RouteCoordinate] = Self.route) -> (TestStoreOf<RouteDetailFeature>, FileStorage) {
        let storage = FileStorage.inMemory
        let store = withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            var state = RouteDetailFeature.State(summary: NorthRouteFixtures.summary(Self.route))
            state.coordinates = coordinates
            return TestStore(initialState: state) {
                RouteDetailFeature()
            } withDependencies: {
                $0.defaultFileStorage = storage
            }
        }
        return (store, storage)
    }

    private func sheet(_ state: RouteDetailFeature.State, wind: [WindSample], storage: FileStorage) -> RouteMapSheetFeature.State {
        withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            RouteMapSheetFeature.State(summary: state.summary, coordinates: state.coordinates, wind: wind)
        }
    }

    @Test("tapping the map opens the sheet on the route and the wind so far")
    func mapTappedOpensTheSheet() async {
        let (store, storage) = makeStore()
        await store.send(.wind(.loaded(Self.samples))) {
            $0.wind.samples = Self.samples
            $0.windExposure = RideWindExposure.alongRoute(Self.route, samples: Self.samples)
        }
        await store.send(.mapTapped) {
            $0.mapSheet = self.sheet($0, wind: Self.samples, storage: storage)
        }
    }

    @Test("with no polyline loaded, tapping the map does nothing")
    func mapTappedWithoutRouteDoesNothing() async {
        let (store, _) = makeStore(coordinates: [])
        await store.send(.mapTapped)
    }

    @Test("wind that lands while the sheet is open reaches it, and the shares are worked out")
    func lateWindReachesTheSheet() async {
        let (store, storage) = makeStore()
        await store.send(.mapTapped) {
            $0.mapSheet = self.sheet($0, wind: [], storage: storage)
        }
        await store.send(.wind(.loaded(Self.samples))) {
            $0.wind.samples = Self.samples
            $0.mapSheet?.wind = Self.samples
            $0.windExposure = RideWindExposure.alongRoute(Self.route, samples: Self.samples)
        }
        #expect(store.state.windExposure != nil)
    }

    @Test("with no sheet open, the wind lands on S20 alone")
    func windWithNoSheet() async {
        let (store, _) = makeStore()
        await store.send(.wind(.loaded(Self.samples))) {
            $0.wind.samples = Self.samples
            $0.windExposure = RideWindExposure.alongRoute(Self.route, samples: Self.samples)
        }
    }

    @Test("a forecast that fails clears the shares and the open sheet's wind")
    func failedForecastClearsTheSheetsWind() async {
        let (store, storage) = makeStore()
        await store.send(.wind(.loaded(Self.samples))) {
            $0.wind.samples = Self.samples
            $0.windExposure = RideWindExposure.alongRoute(Self.route, samples: Self.samples)
        }
        await store.send(.mapTapped) {
            $0.mapSheet = self.sheet($0, wind: Self.samples, storage: storage)
        }
        await store.send(.weatherUnavailable(.offline)) {
            $0.weather = .unavailable(.offline)
            $0.wind.samples = []
            $0.windExposure = nil
            $0.mapSheet?.wind = []
        }
    }

    @Test("the sheet's own options don't touch S20")
    func sheetActionsStayInTheSheet() async {
        let (store, storage) = makeStore()
        await store.send(.mapTapped) {
            $0.mapSheet = self.sheet($0, wind: [], storage: storage)
        }
        await store.send(\.mapSheet.windToggled, false) {
            $0.mapSheet?.showsWind = false
        }
    }
}
