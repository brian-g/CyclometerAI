import ComposableArchitecture
import Foundation
import Testing
@testable import Cyclometer

/// S15 — Ride Detail reading the ride's own track, aggregates and passes rather than
/// the fabricated preview data it used to show (#251).
///
/// The three reads in `.task` are merged, so these tests assert on state once all have settled —
/// `finish()` then `skipReceivedActions()`, for the reason `RouteDetailFeatureTests` spells out.
@MainActor
@Suite("RideDetailFeature")
struct RideDetailFeatureTests {

    // MARK: Harness

    nonisolated private static let summary = RideListSummary(
        id: UUID(), title: "River Loop", startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        distanceMeters: 36_050, durationSeconds: 4_712
    )

    private func makeStore(
        persistenceClient: PersistenceClient,
        healthKitClient: HealthKitClient = .testValue
    ) -> TestStoreOf<RideDetailFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            TestStore(initialState: RideDetailFeature.State(summary: Self.summary)) {
                RideDetailFeature()
            } withDependencies: {
                $0.persistenceClient = persistenceClient
                $0.healthKitClient = healthKitClient
                // The 220 − age estimate reads it.
                $0.date = .constant(Date(timeIntervalSince1970: 1_750_000_000))
                $0.defaultFileStorage = storage
            }
        }
    }

    /// `count` seconds heading north, climbing a metre a second, over two stretches of riding.
    nonisolated static func track(
        count: Int = 20,
        heartRate: (Int) -> Int? = { 120 + $0 },
        cadence: Int? = 90,
        altitude: (Int) -> Double? = { 250 + Double($0) },
        speed: (Int) -> Double = { _ in 6 }
    ) -> [TrackPointDTO] {
        (0..<count).map { second in
            TrackPointDTO(
                rideId: summary.id,
                timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double(second)),
                latitude: 45 + Double(second) * 0.0001,
                longitude: -93,
                altitudeMeters: altitude(second),
                horizontalAccuracyMeters: 5,
                speedMPS: speed(second),
                speedSource: .gps,
                heartRateBPM: heartRate(second),
                heartRateSource: heartRate(second) == nil ? .none : .bleHR,
                cadenceRPM: cadence,
                segmentIndex: second < count / 2 ? 0 : 1
            )
        }
    }

    private static let pass = VehiclePassEventDTO(
        rideId: summary.id, timestamp: Date(timeIntervalSince1970: 1_700_000_005),
        latitude: 45.0005, longitude: -93, alertLevelAtPass: .caution,
        riderSpeedKph: 22, estimatedPassSpeedKph: 61
    )

    private static let stats = RideStats(
        averageSpeedMPS: 6, maxSpeedMPS: 11, averageCadenceRPM: 90, maxCadenceRPM: 104, vehiclePassCount: 1
    )

    private func load(_ store: TestStoreOf<RideDetailFeature>) async {
        store.exhaustivity = .off
        await store.send(.task)
        await store.finish()
        await store.skipReceivedActions()
    }

    // MARK: Loading

    @Test("task loads the track per segment, its metric series, the stats and the passes")
    func taskLoadsEverything() async {
        let points = Self.track()
        let store = makeStore(persistenceClient: .mock(
            trackPoints: [Self.summary.id: points],
            rideStats: [Self.summary.id: Self.stats],
            vehiclePassEvents: [Self.summary.id: [Self.pass]]
        ))

        await load(store)

        #expect(store.state.trackSegments == RideMapThumbnail.drawableSegments(points))
        #expect(store.state.trackSegments.count == 2)
        // `altimeterClient.testValue` has no barometer, so the replay guesses GPS.
        #expect(store.state.track == RideDetailTrack(points: points, altitudeSource: .gps))
        #expect(store.state.track?.heartRate.map(\.bpm) == Array(120..<140))
        #expect(store.state.track?.altitude.first?.meters == 250)
        #expect(store.state.track?.altitude.last?.meters == 269)
        #expect(store.state.stats == Self.stats)
        #expect(store.state.vehiclePasses == [Self.pass])
    }

    @Test("a ride with no HR or cadence sensor has no HR or cadence sections — never zeros")
    func noSensorsLoadEmptyNotZero() async {
        let noSensorStats = RideStats(averageSpeedMPS: 6, maxSpeedMPS: 11)
        let store = makeStore(persistenceClient: .mock(
            trackPoints: [Self.summary.id: Self.track(heartRate: { _ in nil }, cadence: nil)],
            rideStats: [Self.summary.id: noSensorStats]
        ))

        await load(store)

        #expect(store.state.track?.heartRate.isEmpty == true)
        #expect(store.state.heartRateMetrics == nil)
        #expect(store.state.cadence == nil)
        #expect(store.state.stats?.averageCadenceRPM == nil)
        #expect(store.state.stats?.maxCadenceRPM == nil)
        #expect(store.state.stats?.vehiclePassCount == nil)
        #expect(store.state.trackSegments.count == 2)
    }

    @Test("a ride with no drawable track has no segments")
    func noTrackLoadsNothingToDraw() async {
        let store = makeStore(persistenceClient: .mock(
            // One point per segment: nothing a line can be drawn through.
            trackPoints: [Self.summary.id: Self.track(count: 2)],
            rideStats: [Self.summary.id: Self.stats]
        ))

        await load(store)

        #expect(store.state.trackSegments.isEmpty)
        #expect(store.state.stats == Self.stats)
    }

    /// The bands follow Health the way S12's table does, so a rider with a Watch sees zones
    /// from their real resting HR and age rather than the defaults.
    @Test("the HR zone bands resolve against the Health resting HR and age-estimated max")
    func zoneBoundsFollowHealth() async {
        let store = makeStore(
            persistenceClient: .mock(rideStats: [Self.summary.id: Self.stats]),
            // Born mid-1985: 39 on the pinned date, so a 181 bpm estimate.
            healthKitClient: .mock(restingHeartRate: 50, dateOfBirth: DateComponents(year: 1985, month: 7, day: 1))
        )
        let defaults = store.state.heartRateZoneBounds

        await load(store)

        #expect(store.state.healthRestingBPM == 50)
        #expect(store.state.healthMaxBPM == 181)
        #expect(store.state.heartRateZoneBounds != defaults)
        #expect(store.state.heartRateZoneBounds == HeartRateZone.allCases.map {
            HeartRateZone.bounds(for: $0, maxHR: 181, restingHR: 50)
        })
    }

    @Test("the HR zone bands are Health's preferred zones when it has them (#238)")
    func zoneBoundsFollowHealthZones() async {
        let store = makeStore(
            persistenceClient: .mock(rideStats: [Self.summary.id: Self.stats]),
            healthKitClient: .mock(heartRateZoneCeilings: [120, 140, 160, 175])
        )

        await load(store)

        #expect(store.state.heartRateZoneBounds == [60...120, 121...140, 141...160, 161...175, 176...190])
    }

    @Test("a stats read that fails leaves stats nil and the rest of the screen loaded")
    func failedStatsReadLeavesStatsNil() async {
        let points = Self.track()
        // No scripted stats: the mock throws rideNotFound, as live does for an unknown id.
        let store = makeStore(persistenceClient: .mock(trackPoints: [Self.summary.id: points]))

        await load(store)

        #expect(store.state.stats == nil)
        #expect(store.state.trackSegments == RideMapThumbnail.drawableSegments(points))
    }

    // MARK: Route (#426)

    @Test("a ride on a saved route loads that route, for S15's link to S20")
    func aRideOnASavedRouteLoadsTheRoute() async {
        let route = RouteSummary.previewRoutes[1]
        let stats = RideStats(averageSpeedMPS: 6, maxSpeedMPS: 11, routeId: route.id, routeName: route.name)
        let store = makeStore(persistenceClient: .mock(
            rideStats: [Self.summary.id: stats],
            routes: [route]
        ))

        await load(store)

        #expect(store.state.stats == stats)
        #expect(store.state.route == route)
    }

    @Test("a ride whose route was deleted keeps its route's name and loads no route")
    func aDeletedRouteKeepsTheNameOnly() async {
        let stats = RideStats(averageSpeedMPS: 6, maxSpeedMPS: 11, routeId: UUID(), routeName: "Gone Loop")
        // No scripted route: `fetchRouteSummary` comes back nil, as live does for a dangling id.
        let store = makeStore(persistenceClient: .mock(rideStats: [Self.summary.id: stats]))

        await load(store)

        #expect(store.state.stats?.routeName == "Gone Loop")
        #expect(store.state.route == nil)
    }

    @Test("a free ride never asks for a route")
    func aFreeRideReadsNoRoute() async {
        var client = PersistenceClient.mock(rideStats: [Self.summary.id: Self.stats])
        client.fetchRouteSummary = { id in
            Issue.record("fetchRouteSummary(\(id)) for a ride with no route")
            return nil
        }
        let store = makeStore(persistenceClient: client)

        await load(store)

        #expect(store.state.stats == Self.stats)
        #expect(store.state.route == nil)
    }

    @Test("a route read that fails still shows the stats")
    func aFailedRouteReadStillShowsStats() async {
        let stats = RideStats(averageSpeedMPS: 6, maxSpeedMPS: 11, routeId: UUID(), routeName: "River Loop")
        var client = PersistenceClient.mock(rideStats: [Self.summary.id: stats])
        client.fetchRouteSummary = { _ in throw PersistenceError.batchInsertFailed }
        let store = makeStore(persistenceClient: client)

        await load(store)

        #expect(store.state.stats == stats)
        #expect(store.state.route == nil)
    }
}

@Suite("Ride chart point identity")
struct ElevationPointIdentityTests {
    @Test("elevation points are identified by sample index, so the same samples give the same IDs")
    func elevationIDsAreStable() {
        let samples = [12.0, 18.5, 9.25]
        #expect(ElevationPoint.points(from: samples).map(\.id) == [0, 1, 2])
        #expect(ElevationPoint.points(from: samples) == ElevationPoint.points(from: samples))
    }
}

/// #460: S15's stored-at-the-finish rows read their units in words, and are absent without data.
@Suite("S15 finish-stats rows")
struct RideDetailFinishStatsRowTests {
    private let stats = RideStats(
        averageSpeedMPS: 7, maxSpeedMPS: 12,
        averageHeartRateBPM: 142, maxHeartRateBPM: 171,
        ascentMeters: 412, descentMeters: 398, activeKilocalories: 845
    )

    @Test func rowsReadTheirUnitsInWords() {
        #expect(stats.ascent(.metric) == MetricReading(value: "412", unit: "m", spoken: "412 meters"))
        #expect(stats.ascent(.imperial)?.spoken == "1,352 feet")
        #expect(stats.descent(.metric)?.spoken == "398 meters")
        #expect(stats.averageHeartRate == MetricReading(value: "142", unit: "bpm", spoken: "142 beats per minute"))
        #expect(stats.maxHeartRate?.spoken == "171 beats per minute")
        #expect(stats.calories == MetricReading(value: "845", unit: "kcal", spoken: "845 kilocalories"))
    }

    @Test func rowsAreAbsentWithoutData() {
        let none = RideStats(averageSpeedMPS: 7, maxSpeedMPS: 12)
        #expect(none.ascent(.metric) == nil)
        #expect(none.descent(.imperial) == nil)
        #expect(none.averageHeartRate == nil)
        #expect(none.maxHeartRate == nil)
        #expect(none.calories == nil)
    }
}
