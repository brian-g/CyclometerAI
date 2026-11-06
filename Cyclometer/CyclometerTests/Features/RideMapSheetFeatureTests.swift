import ComposableArchitecture
import Foundation
import Testing
@testable import Cyclometer

/// #537 — the map sheet's options, and what S15 hands it.
@MainActor
@Suite("RideMapSheetFeature")
struct RideMapSheetFeatureTests {
    private static let zones = [60...123, 124...143, 144...162, 163...181, 182...200]

    /// 400 m, the first half in HR zone 1 and the second in zone 3, with cadence and altitude.
    private static let points = RideMapFixtures.points(
        count: 40, altitude: { _ in 100 }, heartRate: { $0 < 20 ? 100 : 150 }, cadence: { _ in 88 }
    )

    private func makeStore(
        points: [TrackPointDTO] = Self.points,
        storage: FileStorage = .inMemory
    ) -> TestStoreOf<RideMapSheetFeature> {
        withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            let track = RideMapTrack(points: points)
            return TestStore(initialState: RideMapSheetFeature.State(
                segments: RideMapThumbnail.drawableSegments(points), track: track, passes: [],
                unitSystem: .metric, heartRateZones: Self.zones
            )) {
                RideMapSheetFeature()
            } withDependencies: {
                $0.defaultFileStorage = storage
            }
        }
    }

    // MARK: Coloring

    @Test("a ride offers Plain and each metric it recorded")
    func coloringsFollowTheData() {
        #expect(makeStore().state.availableColorings == [.plain, .speed, .grade, .cadence, .heartRate])
        #expect(makeStore(points: RideMapFixtures.points(count: 40)).state.availableColorings == [.plain, .speed])
    }

    @Test("choosing a coloring colors the route and shows its legend; Plain takes both away")
    func coloringRecolors() async {
        let store = makeStore()
        await store.send(.coloringSelected(.heartRate)) {
            $0.coloring = .heartRate
            $0.coloredRuns = RouteColorScale(coloring: .heartRate, track: $0.track, heartRateZones: Self.zones,
                                             cadenceZones: .default).runs($0.track)
            $0.legend = RouteColorScale(coloring: .heartRate, track: $0.track, heartRateZones: Self.zones,
                                        cadenceZones: .default).legend(.metric)
            $0.legendUnit = "bpm"
        }
        #expect(store.state.coloredRuns.map(\.band) == [1, 3])

        await store.send(.coloringSelected(.plain)) {
            $0.coloring = .plain
            $0.coloredRuns = []
            $0.legend = []
            $0.legendUnit = ""
        }
    }

    @Test("a coloring the ride has no data for can't be chosen")
    func unavailableColoringIsIgnored() async {
        let store = makeStore(points: RideMapFixtures.points(count: 40))
        await store.send(.coloringSelected(.heartRate))
    }

    @Test("new heart rate zones redraw a route colored by heart rate, and only that")
    func zonesRecolorHeartRateOnly() async {
        let store = makeStore()
        store.exhaustivity = .off
        // Every bpm in zone 1 now.
        let wider = [60...160, 161...170, 171...180, 181...190, 191...200]
        await store.send(.coloringSelected(.cadence))
        let cadenceRuns = store.state.coloredRuns
        await store.send(.heartRateZonesChanged(wider))
        #expect(store.state.heartRateZones == wider)
        #expect(store.state.coloredRuns == cadenceRuns)

        await store.send(.coloringSelected(.heartRate))
        #expect(store.state.coloredRuns.map(\.band) == [1])
        await store.send(.heartRateZonesChanged(Self.zones))
        #expect(store.state.coloredRuns.map(\.band) == [1, 3])
    }

    // MARK: Basemap and layers

    @Test("the basemap is remembered for the next sheet, on any ride")
    func basemapIsRemembered() async {
        let storage = FileStorage.inMemory
        let store = makeStore(storage: storage)
        #expect(store.state.basemap == .standard)
        await store.send(.basemapSelected(.hybrid)) {
            $0.$preferences.withLock { $0.rideMapBasemap = .hybrid }
        }

        let next = makeStore(points: RideMapFixtures.points(count: 40), storage: storage)
        #expect(next.state.basemap == .hybrid)
    }

    @Test("the pass and stop layers turn off and on, and start on")
    func layersToggle() async {
        let store = makeStore()
        #expect(store.state.showsPasses && store.state.showsStops)
        await store.send(.passesToggled(false)) { $0.showsPasses = false }
        await store.send(.stopsToggled(false)) { $0.showsStops = false }
        await store.send(.stopsToggled(true)) { $0.showsStops = true }
    }
}

/// What S15 hands its map sheet (#537), and keeps current while it's open.
@MainActor
@Suite("RideDetailFeature — map sheet")
struct RideDetailMapSheetTests {
    private static let summary = RideListSummary(
        id: UUID(), title: "River Loop", startedAt: RideMapFixtures.start, distanceMeters: 2_000, durationSeconds: 300
    )
    /// Two stretches of 100 points, with a 2-minute manual pause between them.
    private static let points = RideMapFixtures.points(count: 100, segment: 0)
        + RideMapFixtures.points(count: 100, from: 100, segment: 1, secondsOffset: 120)
    private static let pauses = [
        RidePause(startedAt: RideMapFixtures.start.addingTimeInterval(100),
                  endedAt: RideMapFixtures.start.addingTimeInterval(220), isAuto: false),
        // Where the ride ended.
        RidePause(startedAt: RideMapFixtures.start.addingTimeInterval(320), endedAt: nil, isAuto: false),
    ]

    private func makeStore(stats: RideStats?) -> TestStoreOf<RideDetailFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            var state = RideDetailFeature.State(summary: Self.summary)
            state.trackSegments = RideMapThumbnail.drawableSegments(Self.points)
            state.track = RideDetailTrack(points: Self.points, altitudeSource: .gps)
            state.stats = stats
            let store = TestStore(initialState: state) {
                RideDetailFeature()
            } withDependencies: {
                $0.defaultFileStorage = storage
            }
            store.exhaustivity = .off
            return store
        }
    }

    private var mapSheet: (TestStoreOf<RideDetailFeature>) -> RideMapSheetFeature.State? {
        { store in
            guard case let .mapSheet(sheet) = store.state.destination else { return nil }
            return sheet
        }
    }

    @Test("the sheet opens with the ride's stops, and a pass layer only with a radar")
    func sheetOpensSeeded() async throws {
        let store = makeStore(stats: RideStats(averageSpeedMPS: 6, maxSpeedMPS: 9, vehiclePassCount: 0, pauses: Self.pauses))
        await store.send(.mapTapped)
        let sheet = try #require(mapSheet(store))
        #expect(sheet.stops.map(\.duration) == [120])
        #expect(sheet.hasRadar)
        #expect(sheet.track.segments.count == 2)

        let noRadar = makeStore(stats: RideStats(averageSpeedMPS: 6, maxSpeedMPS: 9))
        await noRadar.send(.mapTapped)
        #expect(try #require(mapSheet(noRadar)).hasRadar == false)
        #expect(try #require(mapSheet(noRadar)).stops.isEmpty, "a ride recorded before pauses were")
    }

    @Test("stats that land after the sheet opened bring it the stops and the pass layer")
    func lateStatsReachTheSheet() async throws {
        let store = makeStore(stats: nil)
        await store.send(.mapTapped)
        #expect(try #require(mapSheet(store)).stops.isEmpty)

        await store.send(.statsLoaded(RideStats(averageSpeedMPS: 6, maxSpeedMPS: 9, vehiclePassCount: 2, pauses: Self.pauses),
                                      route: nil))
        let sheet = try #require(mapSheet(store))
        #expect(sheet.stops.count == 1)
        #expect(sheet.hasRadar)
    }

    @Test("Health's zones landing while the sheet is open reach it")
    func lateZonesReachTheSheet() async throws {
        let store = makeStore(stats: RideStats(averageSpeedMPS: 6, maxSpeedMPS: 9))
        await store.send(.mapTapped)
        await store.send(.healthProfileFetched(restingBPM: 50, maxBPM: 190, zoneCeilingsBPM: nil))
        await store.receive(\.destination.presented.mapSheet.heartRateZonesChanged)
        #expect(try #require(mapSheet(store)).heartRateZones == store.state.heartRateZoneBounds)
    }

    @Test("with no sheet open, Health's zones send nothing to it")
    func zonesWithNoSheetSendNothing() async {
        let store = makeStore(stats: nil)
        store.exhaustivity = .on
        await store.send(.healthProfileFetched(restingBPM: 50, maxBPM: 190, zoneCeilingsBPM: nil)) {
            $0.healthRestingBPM = 50
            $0.healthMaxBPM = 190
        }
    }
}
