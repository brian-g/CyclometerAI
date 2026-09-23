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

    private static let summary = RideListSummary(
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
        cadence: Int? = 90
    ) -> [TrackPointDTO] {
        (0..<count).map { second in
            TrackPointDTO(
                rideId: summary.id,
                timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double(second)),
                latitude: 45 + Double(second) * 0.0001,
                longitude: -93,
                altitudeMeters: 250 + Double(second),
                horizontalAccuracyMeters: 5,
                speedMPS: 6,
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

    @Test("task loads the track per segment, its elevation and HR series, the stats and the passes")
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
        let profile = store.state.elevationProfileMeters
        #expect(profile?.count == RideDetailFeature.chartSampleCount)
        #expect(profile?.first == 250)
        #expect(profile?.last == 269)
        #expect(store.state.heartRateSamples == Array(120..<140))
        #expect(store.state.stats == Self.stats)
        #expect(store.state.vehiclePasses == [Self.pass])
    }

    @Test("a ride with no HR or cadence sensor loads no HR series and nil cadence — never zeros")
    func noSensorsLoadEmptyNotZero() async {
        let noSensorStats = RideStats(averageSpeedMPS: 6, maxSpeedMPS: 11)
        let store = makeStore(persistenceClient: .mock(
            trackPoints: [Self.summary.id: Self.track(heartRate: { _ in nil }, cadence: nil)],
            rideStats: [Self.summary.id: noSensorStats]
        ))

        await load(store)

        #expect(store.state.heartRateSamples.isEmpty)
        #expect(store.state.stats?.averageCadenceRPM == nil)
        #expect(store.state.stats?.maxCadenceRPM == nil)
        #expect(store.state.stats?.vehiclePassCount == nil)
        #expect(store.state.trackSegments.count == 2)
    }

    @Test("a ride with no drawable track has no segments and no elevation profile")
    func noTrackLoadsNothingToDraw() async {
        let store = makeStore(persistenceClient: .mock(
            // One point per segment: nothing a line can be drawn through.
            trackPoints: [Self.summary.id: Self.track(count: 2)],
            rideStats: [Self.summary.id: Self.stats]
        ))

        await load(store)

        #expect(store.state.trackSegments.isEmpty)
        #expect(store.state.elevationProfileMeters == nil)
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

    @Test("a stats read that fails leaves stats nil and the rest of the screen loaded")
    func failedStatsReadLeavesStatsNil() async {
        let points = Self.track()
        // No scripted stats: the mock throws rideNotFound, as live does for an unknown id.
        let store = makeStore(persistenceClient: .mock(trackPoints: [Self.summary.id: points]))

        await load(store)

        #expect(store.state.stats == nil)
        #expect(store.state.trackSegments == RideMapThumbnail.drawableSegments(points))
    }
}

@Suite("RideDetailSeries")
struct RideDetailSeriesTests {

    private static func points(heartRates: [Int?]) -> [TrackPointDTO] {
        heartRates.enumerated().map { second, bpm in
            TrackPointDTO(rideId: UUID(), timestamp: Date(timeIntervalSince1970: Double(second)),
                          latitude: 45, longitude: -93, altitudeMeters: 0, horizontalAccuracyMeters: 5,
                          speedMPS: nil, speedSource: .none,
                          heartRateBPM: bpm, heartRateSource: bpm == nil ? .none : .bleHR, cadenceRPM: nil)
        }
    }

    @Test("fewer readings than buckets come back as they are, gaps dropped")
    func fewerReadingsThanBuckets() {
        #expect(RideDetailSeries.heartRate(Self.points(heartRates: [100, nil, 110, 120]), sampleCount: 10)
                == [100, 110, 120])
    }

    @Test("more readings than buckets are averaged, in order, into exactly that many")
    func readingsAreBucketAveraged() {
        let series = RideDetailSeries.heartRate(Self.points(heartRates: [100, 102, 110, 112, 120, 124]), sampleCount: 3)
        #expect(series == [101, 111, 122])
    }

    @Test("no readings at all is an empty series, not zeros")
    func noReadingsIsEmpty() {
        #expect(RideDetailSeries.heartRate(Self.points(heartRates: [nil, nil, nil]), sampleCount: 3).isEmpty)
    }
}

@Suite("HeartRateProfileView layout")
struct HeartRateProfileLayoutTests {
    /// §8's worked example: resting 60, max 190.
    private static let bounds = HeartRateZone.allCases.map { HeartRateZone.bounds(for: $0, maxHR: 190, restingHR: 60) }

    @Test("the domain fits the ride, padded, and only the zones it reaches get a band")
    func domainFitsTheRide() {
        let layout = HeartRateProfileView.layout(samples: [120, 145, 160], zoneBounds: Self.bounds)

        #expect(layout.domain == 115...165)
        // Zone edges at 138, 151, 164: zones 1–4 are in reach, zone 5 is not.
        #expect(layout.bands == [
            .init(zone: 1, bpm: 115...138), .init(zone: 2, bpm: 138...151),
            .init(zone: 3, bpm: 151...164), .init(zone: 4, bpm: 164...165)
        ])
    }

    @Test("a ride inside one zone is one band over the whole domain")
    func oneZoneRide() {
        let layout = HeartRateProfileView.layout(samples: [100, 110], zoneBounds: Self.bounds)
        #expect(layout.bands == [.init(zone: 1, bpm: 95...115)])
    }

    @Test("readings above max sit in a zone 5 band that runs to the top of the domain")
    func aboveMaxIsZone5() {
        let layout = HeartRateProfileView.layout(samples: [185, 200], zoneBounds: Self.bounds)
        #expect(layout.bands == [.init(zone: 5, bpm: 180...205)])
    }
}
